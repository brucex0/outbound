import { assertNoBlockedGroupMember, GroupDomainError } from "./groups.js";
import { getPrismaClient } from "./prisma.js";

// Visibility alone (for example public discovery) never grants participation.
export async function eligibleActivityEvent(userId: string, id: string) {
  const prisma = getPrismaClient();
  const event = await prisma.activityEvent.findUnique({ where: { id } });
  if (!event) return null;
  const blocked = await prisma.socialBlock.findFirst({ where: { OR: [
    { blockerId: userId, blockedId: event.creatorId },
    { blockerId: event.creatorId, blockedId: userId },
  ] } });
  if (blocked) return null;
  if (event.groupId) {
    const member = await prisma.groupMember.findFirst({ where: { groupId: event.groupId, userId, status: "active" } });
    if (!member) return null;
    try { await assertNoBlockedGroupMember(event.groupId, userId); }
    catch (error) { if (error instanceof GroupDomainError) return null; throw error; }
    return event;
  }
  if (event.creatorId === userId) return event;
  const invitation = await prisma.invitation.findFirst({ where: { activityEventId: id, recipientId: userId, status: { in: ["pending", "accepted"] } } });
  const participant = await prisma.activityEventParticipant.findUnique({ where: { activityEventId_userId: { activityEventId: id, userId } } });
  const connection = event.visibility === "connections" ? await prisma.connection.findFirst({ where: { status: "accepted", OR: [
    { requesterId: userId, addresseeId: event.creatorId }, { requesterId: event.creatorId, addresseeId: userId },
  ] } }) : null;
  return invitation || participant || connection ? event : null;
}

export async function startEventParticipation(userId: string, activityEventId: string, startedAt = new Date()) {
  const prisma = getPrismaClient();
  await prisma.activityEventParticipant.upsert({
    where: { activityEventId_userId: { activityEventId, userId } },
    create: { activityEventId, userId, status: "participating", startedAt },
    update: {},
  });
  // Concurrent retries must not overwrite a recording that has already resolved.
  return prisma.activityEventParticipant.updateMany({
    where: { activityEventId, userId, startedAt: null },
    data: { startedAt, outcome: null, resolvedAt: null },
  });
}
