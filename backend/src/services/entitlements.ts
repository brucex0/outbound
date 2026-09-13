import { createHash, randomBytes } from "node:crypto";
import { Prisma, type PrismaClient } from "@prisma/client";
import { isFoundingMember } from "./foundingMembers.js";

export const PAID_CAPABILITIES = [
  "ai_planning_dynamic",
  "live_coach_dynamic",
  "live_cheer_voice",
] as const;
export type PaidCapability = typeof PAID_CAPABILITIES[number];
export const PLUS_BUNDLE = "plus";
export const REVENUECAT_ENTITLEMENT_SOURCE = "revenuecat";
export const REFERRAL_PROGRAM = {
  termsVersion: 1,
  inviteeRewardDays: 30,
  inviterRewardDays: 30,
  claimWindowDays: 7,
  qualifyingActivitySeconds: 10 * 60,
} as const;

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export function normalizeRewardCode(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function entitlementCodeDigest(value: string): string {
  return createHash("sha256").update(normalizeRewardCode(value)).digest("hex");
}

export function formatRewardCode(value: string): string {
  return normalizeRewardCode(value).match(/.{1,4}/g)?.join("-") ?? value;
}

export function generateEntitlementCode(): string {
  return formatRewardCode(randomBytes(12).toString("hex"));
}

export async function ensurePersonalReferralCode(prisma: PrismaClient, userId: string): Promise<string> {
  const existing = await prisma.referralLink.findUnique({ where: { creatorId: userId } });
  if (existing) return existing.code;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = randomReadableCode();
    try {
      const created = await prisma.referralLink.create({ data: { creatorId: userId, code } });
      return formatRewardCode(created.code);
    } catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") throw error;
      const raced = await prisma.referralLink.findUnique({ where: { creatorId: userId } });
      if (raced) return raced.code;
    }
  }
  throw new Error("referral_code_unavailable");
}

export async function hasActiveCapability(
  prisma: DatabaseClient,
  userId: string,
  capability: PaidCapability,
  now = new Date(),
): Promise<boolean> {
  return (await prisma.featureEntitlement.count({ where: {
    userId,
    capability,
    status: "active",
    startsAt: { lte: now },
    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
  } })) > 0;
}

export async function entitlementSummary(prisma: PrismaClient, userId: string, now = new Date()) {
  const grants = await prisma.featureEntitlement.findMany({
    where: { userId, status: "active", startsAt: { lte: now }, OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
    orderBy: { createdAt: "desc" },
  });
  return PAID_CAPABILITIES.map((capability) => {
    const matching = grants.filter((grant) => grant.capability === capability);
    const permanent = matching.some((grant) => grant.expiresAt == null);
    const expiresAt = permanent ? null : matching.reduce<Date | null>((latest, grant) =>
      !latest || (grant.expiresAt && grant.expiresAt > latest) ? grant.expiresAt : latest, null);
    return { capability, allowed: matching.length > 0, expiresAt, sources: [...new Set(matching.map((grant) => grant.source))] };
  });
}

export async function referralProgramForUser(prisma: DatabaseClient, userId: string) {
  const foundingMember = await isFoundingMember(prisma, userId);
  return {
    ...REFERRAL_PROGRAM,
    inviterRewardDays: foundingMember ? 0 : REFERRAL_PROGRAM.inviterRewardDays,
    inviterRewardEligible: !foundingMember,
    foundingMember,
  };
}

export async function bankedPlusDays(prisma: PrismaClient, userId: string, now = new Date()): Promise<number> {
  const credit = await prisma.featureEntitlement.findUnique({
    where: { userId_capability_source: { userId, capability: PAID_CAPABILITIES[0], source: "earned_plus" } },
    select: { startsAt: true, expiresAt: true, status: true },
  });
  if (!credit?.expiresAt || credit.status !== "active" || credit.startsAt <= now) return 0;
  return Math.max(0, Math.round((credit.expiresAt.getTime() - credit.startsAt.getTime()) / 86_400_000));
}

export async function setRevenueCatPlusEntitlement(
  prisma: PrismaClient,
  userId: string,
  subscription: { active: boolean; startsAt: Date; expiresAt: Date | null },
): Promise<void> {
  const now = new Date();
  await prisma.$transaction(async (tx) => {
    for (const capability of PAID_CAPABILITIES) {
      await tx.featureEntitlement.upsert({
        where: {
          userId_capability_source: {
            userId,
            capability,
            source: REVENUECAT_ENTITLEMENT_SOURCE,
          },
        },
        update: {
          status: subscription.active ? "active" : "expired",
          startsAt: subscription.startsAt,
          expiresAt: subscription.expiresAt,
        },
        create: {
          userId,
          capability,
          source: REVENUECAT_ENTITLEMENT_SOURCE,
          status: subscription.active ? "active" : "expired",
          startsAt: subscription.startsAt,
          expiresAt: subscription.expiresAt,
        },
      });
      const earned = await tx.featureEntitlement.findUnique({
        where: { userId_capability_source: { userId, capability, source: "earned_plus" } },
      });
      if (earned?.expiresAt && earned.status === "active" && earned.expiresAt > now) {
        if (subscription.active && subscription.expiresAt && subscription.expiresAt > now) {
          const rewardStart = earned.startsAt > now ? earned.startsAt : now;
          const remainingMilliseconds = earned.expiresAt.getTime() - rewardStart.getTime();
          if (remainingMilliseconds > 0 && rewardStart < subscription.expiresAt) {
            await tx.featureEntitlement.update({
              where: { id: earned.id },
              data: {
                startsAt: subscription.expiresAt,
                expiresAt: new Date(subscription.expiresAt.getTime() + remainingMilliseconds),
              },
            });
          }
        } else if (earned.startsAt > now) {
          const savedMilliseconds = earned.expiresAt.getTime() - earned.startsAt.getTime();
          await tx.featureEntitlement.update({
            where: { id: earned.id },
            data: {
              startsAt: now,
              expiresAt: new Date(now.getTime() + savedMilliseconds),
            },
          });
        }
      }
    }
  });
}

export async function claimReferral(prisma: PrismaClient, inviteeId: string, rawCode: string) {
  const code = rawCode.trim();
  return prisma.$transaction(async (tx) => {
    const [invitee, referralCode, existing] = await Promise.all([
      tx.user.findUnique({ where: { id: inviteeId }, select: { id: true, createdAt: true } }),
      tx.referralLink.findFirst({ where: { OR: [{ code }, { code: normalizeRewardCode(code) }] } }),
      tx.referralClaim.findUnique({ where: { claimantId: inviteeId } }),
    ]);
    if (!invitee || !referralCode) throw new RewardCodeError("invalid_referral_code");
    if (existing) throw new RewardCodeError("referral_already_claimed");
    if (referralCode.creatorId === inviteeId) throw new RewardCodeError("self_referral_not_allowed");
    if (invitee.createdAt < addDays(new Date(), -REFERRAL_PROGRAM.claimWindowDays)) throw new RewardCodeError("referral_window_closed");
    const inviterIsFoundingMember = await isFoundingMember(tx, referralCode.creatorId);
    const claim = await tx.referralClaim.create({ data: {
      referralLinkId: referralCode.id,
      claimantId: inviteeId,
      rewardDays: inviterIsFoundingMember ? 0 : REFERRAL_PROGRAM.inviterRewardDays,
      inviteeRewardDays: REFERRAL_PROGRAM.inviteeRewardDays,
      qualifyingActivitySeconds: REFERRAL_PROGRAM.qualifyingActivitySeconds,
      termsVersion: REFERRAL_PROGRAM.termsVersion,
    } });
    await tx.referralLink.update({ where: { id: referralCode.id }, data: { claimCount: { increment: 1 } } });
    await grantBundle(tx, inviteeId, claim.inviteeRewardDays, "referral_welcome", `referral-welcome:${claim.id}`);
    return claim;
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

export async function qualifyReferralFromActivity(prisma: PrismaClient, userId: string, durationSeconds: number | null | undefined) {
  return prisma.$transaction(async (tx) => {
    const claim = await tx.referralClaim.findUnique({
      where: { claimantId: userId },
      include: { referralLink: { select: { creatorId: true } } },
    });
    if (!claim || claim.rewardedAt || (durationSeconds ?? 0) < claim.qualifyingActivitySeconds) return false;
    const now = new Date();
    const inviterIsFoundingMember = await isFoundingMember(tx, claim.referralLink.creatorId);
    if (!inviterIsFoundingMember && claim.rewardDays > 0) {
      await grantBundle(tx, claim.referralLink.creatorId, claim.rewardDays, "referral_reward", `referral-reward:${claim.id}`);
    }
    await tx.referralClaim.update({ where: { id: claim.id }, data: { status: "rewarded", qualifiedAt: now, rewardedAt: now } });
    return true;
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

export async function redeemEntitlementCode(prisma: PrismaClient, userId: string, rawCode: string) {
  const digest = entitlementCodeDigest(rawCode);
  return prisma.$transaction(async (tx) => {
    const code = await tx.entitlementCode.findUnique({ where: { codeDigest: digest } });
    const now = new Date();
    if (!code || code.status !== "active" || (code.expiresAt && code.expiresAt <= now)) throw new RewardCodeError("invalid_entitlement_code");
    if (code.redemptionCount >= code.maxRedemptions) throw new RewardCodeError("entitlement_code_exhausted");
    const prior = await tx.entitlementCodeRedemption.findUnique({ where: { codeId_userId: { codeId: code.id, userId } } });
    if (prior) throw new RewardCodeError("entitlement_code_already_redeemed");
    const redemption = await tx.entitlementCodeRedemption.create({ data: { codeId: code.id, userId } });
    const updated = await tx.entitlementCode.updateMany({
      where: { id: code.id, status: "active", redemptionCount: { lt: code.maxRedemptions } },
      data: { redemptionCount: { increment: 1 } },
    });
    if (updated.count !== 1) throw new RewardCodeError("entitlement_code_exhausted");
    await grantBundle(tx, userId, code.durationDays, `contribution:${code.bundle}`, `entitlement-code:${redemption.id}`);
    return { bundle: code.bundle, durationDays: code.durationDays };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

async function grantBundle(tx: Prisma.TransactionClient, userId: string, days: number, source: string, reference: string) {
  const now = new Date();
  const referenceHash = createHash("sha256").update(reference).digest("hex");
  for (const capability of PAID_CAPABILITIES) {
    const ledgerExists = await tx.entitlementGrantLedger.findUnique({ where: {
      userId_capability_sourceReferenceHash: { userId, capability, sourceReferenceHash: referenceHash },
    } });
    if (ledgerExists) continue;
    const current = await tx.featureEntitlement.findUnique({ where: {
      userId_capability_source: { userId, capability, source: "earned_plus" },
    } });
    const paid = await tx.featureEntitlement.findUnique({ where: {
      userId_capability_source: { userId, capability, source: REVENUECAT_ENTITLEMENT_SOURCE },
    } });
    const paidUntil = paid?.status === "active" && paid.expiresAt && paid.expiresAt > now ? paid.expiresAt : now;
    const existingActive = current?.status === "active" && current.expiresAt && current.expiresAt > now;
    let startsAt = paidUntil;
    let expiresAt = addDays(paidUntil, days);
    if (existingActive) {
      const remainingStart = current.startsAt > now ? current.startsAt : now;
      const remainingMilliseconds = current.expiresAt!.getTime() - remainingStart.getTime();
      if (paidUntil > remainingStart) {
        startsAt = paidUntil;
        expiresAt = addDays(new Date(paidUntil.getTime() + remainingMilliseconds), days);
      } else {
        startsAt = current.startsAt;
        expiresAt = addDays(current.expiresAt!, days);
      }
    }
    await tx.featureEntitlement.upsert({
      where: { userId_capability_source: { userId, capability, source: "earned_plus" } },
      update: { status: "active", startsAt, expiresAt },
      create: { userId, capability, source: "earned_plus", status: "active", startsAt, expiresAt },
    });
    await tx.entitlementGrantLedger.create({ data: {
      userId, capability, source, sourceReferenceHash: referenceHash, durationDays: days, startsAt: now, expiresAt,
    } });
  }
}

function addDays(value: Date, days: number): Date {
  return new Date(value.getTime() + days * 86_400_000);
}

function randomReadableCode(): string {
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const bytes = randomBytes(8);
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join("");
}

export class RewardCodeError extends Error {
  constructor(readonly code: string) { super(code); }
}
