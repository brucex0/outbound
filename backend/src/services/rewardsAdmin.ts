import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { Context, MiddlewareHandler } from "hono";
import type { Prisma, PrismaClient, User } from "@prisma/client";
import type { AppEnv } from "../types/hono.js";
import { getAuthenticatedAppUser } from "./currentUser.js";
import { formatRewardCode, normalizeRewardCode, PAID_CAPABILITIES } from "./entitlements.js";
import { getPrismaClient } from "./prisma.js";

export type RewardsAdminActor = Pick<User, "id" | "normalizedEmail" | "displayName">;
type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export const rewardsAdminMiddleware: MiddlewareHandler<AppEnv> = async (c, next) => {
  const configured = configuredAdminEmails();
  if (configured.size === 0) {
    return c.json({ error: "Rewards administration is not configured.", code: "admin_not_configured" }, 503);
  }
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const verifiedIdentity = await getPrismaClient().authIdentity.findFirst({
    where: { userId: user.id, emailVerified: true, normalizedEmail: { in: [...configured] } },
    select: { normalizedEmail: true },
  });
  if (!verifiedIdentity?.normalizedEmail) {
    return c.json({ error: "Administrator access required.", code: "admin_access_required" }, 403);
  }
  c.set("rewardsAdmin", { id: user.id, normalizedEmail: verifiedIdentity.normalizedEmail, displayName: user.displayName });
  await next();
};

export function configuredAdminEmails(): Set<string> {
  return new Set((process.env.REWARDS_ADMIN_EMAILS ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean));
}

export function rewardsAdmin(c: Context<AppEnv>): RewardsAdminActor {
  const actor = c.get("rewardsAdmin");
  if (!actor) throw new Error("rewards_admin_context_missing");
  return actor;
}

export async function issueAdminEntitlementCode(
  prisma: DatabaseClient,
  input: { label: string; durationDays: number; maxRedemptions: number; expiresAt?: Date | null },
) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = formatRewardCode(randomBytes(12).toString("hex"));
    try {
      const record = await prisma.entitlementCode.create({ data: {
        codeDigest: codeDigest(code),
        label: input.label,
        durationDays: input.durationDays,
        maxRedemptions: input.maxRedemptions,
        expiresAt: input.expiresAt ?? null,
      } });
      return { record, code };
    } catch (error) {
      if (!isUniqueConflict(error)) throw error;
    }
  }
  throw new Error("entitlement_code_generation_failed");
}

export async function grantAdminPlus(
  prisma: DatabaseClient,
  userId: string,
  input: { durationDays: number | null; reason: string },
) {
  const now = new Date();
  const reference = randomUUID();
  const referenceHash = createHash("sha256").update(`admin-grant:${reference}`).digest("hex");
  const expiresAt = input.durationDays == null ? null : new Date(now.getTime() + input.durationDays * 86_400_000);
  const entitlements: Prisma.FeatureEntitlementGetPayload<Record<string, never>>[] = [];
  for (const capability of PAID_CAPABILITIES) {
      const sourceReferenceHash = createHash("sha256").update(`${referenceHash}:${capability}`).digest("hex");
      const entitlement = await prisma.featureEntitlement.create({ data: {
        userId,
        capability,
        source: `admin:${reference}`,
        status: "active",
        sourceReferenceHash,
        startsAt: now,
        expiresAt,
      } });
      await prisma.entitlementGrantLedger.create({ data: {
        userId,
        capability,
        source: "admin_grant",
        sourceReferenceHash,
        durationDays: input.durationDays,
        startsAt: now,
        expiresAt,
      } });
      entitlements.push(entitlement);
    }
  return { reference, expiresAt, entitlements };
}

export async function auditRewardAdminAction(
  prisma: PrismaClient | Prisma.TransactionClient,
  actor: RewardsAdminActor,
  event: { action: string; targetType: string; targetId: string; reason?: string | null; metadata?: Prisma.InputJsonValue },
) {
  return prisma.adminRewardAuditEvent.create({ data: {
    actorUserId: actor.id,
    action: event.action,
    targetType: event.targetType,
    targetId: event.targetId,
    reason: event.reason?.trim().slice(0, 500) || null,
    metadata: event.metadata,
  } });
}

function codeDigest(value: string): string {
  return createHash("sha256").update(normalizeRewardCode(value)).digest("hex");
}

function isUniqueConflict(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "P2002";
}
