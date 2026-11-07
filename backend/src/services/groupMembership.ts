import { Prisma } from "@prisma/client";
import { isRetryableGroupTransaction } from "./groupLock.js";
import { getPrismaClient } from "./prisma.js";
import { compactPerson } from "./apiAssetURLs.js";
import { GroupDomainError } from "./groups.js";

type Database = Prisma.TransactionClient;
const personSelect = { id: true, displayName: true, avatarUrl: true } as const;

export async function membershipTransaction<T>(operation: (db: Database) => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await getPrismaClient().$transaction(operation, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if (!isRetryableGroupTransaction(error)) throw error;
      // Concurrent admissions/reviews are normal; retry the whole decision with
      // fresh policy, membership and capacity rather than a stale partial write.
      console.info("[socialGroup] retrying membership transaction", { operation: "change group membership", attempt: attempt + 1 });
    }
  }
  throw new GroupDomainError("concurrent_update", "The Group changed. Try again.");
}

// Rechecked at delivery, acceptance and approval: an old invitation is never an
// authority to bypass current membership, connection, block or archive rules.
export async function assertInvitationEligibility(groupId: string, senderId: string, recipientId: string, db: Database = getPrismaClient(), requireMemberConnection = false) {
  const group = await db.socialGroup.findUnique({ where: { id: groupId } });
  const sender = await db.groupMember.findUnique({ where: { groupId_userId: { groupId, userId: senderId } } });
  if (!group || group.lifecycle === "archived" || sender?.status !== "active" || (group.trustPolicy === "trusted_private" && !group.ownerId)) throw new GroupDomainError("invitation_unavailable", "This Group invitation is unavailable.");
  const members = await db.groupMember.findMany({ where: { groupId, status: "active" }, select: { userId: true } });
  const blocked = await db.socialBlock.findFirst({ where: { OR: [...new Set([...members.map((m) => m.userId), senderId])].flatMap((id) => [{ blockerId: recipientId, blockedId: id }, { blockerId: id, blockedId: recipientId }]) }, select: { id: true } });
  if (blocked) throw new GroupDomainError("blocked", "This Group invitation is unavailable.");
  const requiredConnections = group.trustPolicy === "trusted_private" ? [senderId, group.ownerId] : requireMemberConnection ? [senderId] : [];
  // Member invite pickers use accepted connections at delivery. Community
  // invitations retain their block-only acceptance rule. Private Groups also
  // retain the owner's connection boundary at every step.
  for (const id of new Set(requiredConnections.filter((id): id is string => Boolean(id)))) {
    if (id === recipientId) continue;
    const connection = await db.connection.findFirst({ where: { status: "accepted", OR: [{ requesterId: id, addresseeId: recipientId }, { requesterId: recipientId, addresseeId: id }] }, select: { id: true } });
    if (!connection) throw new GroupDomainError("accepted_connection_required", "An accepted connection is required for this invitation.");
  }
  return { group, sender };
}

export async function membershipControls(groupId: string, viewerId: string) {
  const db = getPrismaClient();
  const member = await db.groupMember.findUnique({ where: { groupId_userId: { groupId, userId: viewerId } }, select: { role: true, status: true } });
  const canReview = member?.status === "active" && ["owner", "admin"].includes(member.role);
  const [joinRequests, pendingRequestCount] = canReview ? await Promise.all([
    db.groupJoinRequest.findMany({ where: { groupId, status: "pending" }, include: { requester: { select: personSelect }, sourceInvitation: { select: { sender: { select: personSelect } } } }, orderBy: [{ createdAt: "asc" }, { id: "asc" }], take: 50 }),
    db.groupJoinRequest.count({ where: { groupId, status: "pending" } }),
  ]) : [[], 0] as const;
  return { pendingRequestCount, joinRequests: joinRequests.map((request) => ({ id: request.id, requester: compactPerson(request.requester), inviter: request.sourceInvitation ? compactPerson(request.sourceInvitation.sender) : null, createdAt: request.createdAt })) };
}

export async function notifyMembershipReview(groupId: string, requesterId: string, requestId: string) {
  const db = getPrismaClient();
  const managers = await db.groupMember.findMany({ where: { groupId, status: "active", role: { in: ["owner", "admin"] } }, select: { userId: true } });
  await db.socialNotification.createMany({ data: managers.map(({ userId }) => ({ recipientId: userId, actorId: requesterId, type: "groupJoinRequest", objectId: groupId, message: "A Group membership request is ready for review.", dedupeKey: `groupJoinRequest:${requestId}:${userId}` })), skipDuplicates: true });
}
