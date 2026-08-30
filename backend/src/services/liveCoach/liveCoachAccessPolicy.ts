import { Prisma, type PrismaClient } from "@prisma/client";
import type { LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import type { LiveCoachAccessDecision } from "./liveCoachTypes.js";

export const LIVE_COACH_CAPABILITY = "live_coach_dynamic";
export const LIVE_COACH_FOUNDING_SOURCE = "founding_beta_1000";
export const LIVE_COACH_TRIAL_PERIOD_KEY = "three_run_trial_v1";

export interface LiveCoachEntitlementResolver {
  resolve(userId: string, now: Date, config: LiveCoachFeatureConfig): Promise<LiveCoachAccessDecision>;
}

export class DatabaseLiveCoachEntitlementResolver implements LiveCoachEntitlementResolver {
  constructor(private readonly prisma: PrismaClient) {}

  async resolve(userId: string, now: Date, config: LiveCoachFeatureConfig): Promise<LiveCoachAccessDecision> {
    if (config.mode !== "dynamic") return decision(false, "feature_disabled");
    if (config.accessMode === "open_beta") return decision(true, "open_beta");

    const entitlement = await this.activeEntitlement(userId, now);
    if (entitlement) return decision(true, promotionSources.has(entitlement.source) ? "promotion" : "verified_subscription");

    if (config.accessMode === "subscription_required") return decision(false, "entitlement_required");

    const foundingEntitlement = await this.ensureFoundingEntitlement(userId, now, config.foundingUserLimit);
    if (foundingEntitlement) return decision(true, "promotion");

    await this.releaseExpiredTrialReservations(userId, now);
    const usage = await this.prisma.featureUsagePeriod.findUnique({
      where: { userId_capability_periodKey: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
      }},
    });
    const consumed = (usage?.successfulCount ?? 0) + (usage?.reservedCount ?? 0);
    return consumed < config.trialRunLimit
      ? decision(true, "open_beta")
      : decision(false, "entitlement_required");
  }

  async reserveTrialRun(userId: string, config: LiveCoachFeatureConfig): Promise<boolean> {
    if (config.accessMode !== "founding_trial") return false;
    const usage = await this.prisma.featureUsagePeriod.upsert({
      where: { userId_capability_periodKey: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
      }},
      update: { limitSnapshot: config.trialRunLimit },
      create: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
        limitSnapshot: config.trialRunLimit,
      },
    });
    const updated = await this.prisma.$executeRaw`
      UPDATE "FeatureUsagePeriod"
      SET "reservedCount" = "reservedCount" + 1,
          "limitSnapshot" = ${config.trialRunLimit},
          "updatedAt" = NOW()
      WHERE "id" = ${usage.id}
        AND "reservedCount" + "successfulCount" < ${config.trialRunLimit}
    `;
    return updated === 1;
  }

  async finalizeTrialRun(userId: string): Promise<void> {
    await this.prisma.featureUsagePeriod.updateMany({
      where: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
        reservedCount: { gt: 0 },
      },
      data: {
        reservedCount: { decrement: 1 },
        successfulCount: { increment: 1 },
      },
    });
  }

  async releaseTrialRun(userId: string): Promise<void> {
    await this.prisma.featureUsagePeriod.updateMany({
      where: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
        reservedCount: { gt: 0 },
      },
      data: { reservedCount: { decrement: 1 } },
    });
  }

  private activeEntitlement(userId: string, now: Date) {
    return this.prisma.featureEntitlement.findFirst({
      where: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        status: "active",
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: "desc" },
    });
  }

  private async ensureFoundingEntitlement(userId: string, now: Date, limit: number) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { id: true, createdAt: true } });
    if (!user) return null;
    const ordinal = await this.prisma.user.count({
      where: { OR: [
        { createdAt: { lt: user.createdAt } },
        { createdAt: user.createdAt, id: { lte: user.id } },
      ]},
    });
    if (ordinal > limit) return null;
    return this.prisma.featureEntitlement.upsert({
      where: { userId_capability_source: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        source: LIVE_COACH_FOUNDING_SOURCE,
      }},
      update: { status: "active", expiresAt: null },
      create: {
        userId,
        capability: LIVE_COACH_CAPABILITY,
        source: LIVE_COACH_FOUNDING_SOURCE,
        status: "active",
        startsAt: now,
      },
    });
  }

  private async releaseExpiredTrialReservations(userId: string, now: Date): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      const expired = await tx.liveCoachSession.updateMany({
        where: {
          userId,
          status: "active",
          effectiveAudioMode: "dynamic",
          accessReason: "open_beta",
          dynamicCueCount: 0,
          expiresAt: { lte: now },
        },
        data: { status: "expired", endedAt: now },
      });
      if (expired.count === 0) return;
      await tx.$executeRaw`
        UPDATE "FeatureUsagePeriod"
        SET "reservedCount" = GREATEST(0, "reservedCount" - ${expired.count}),
            "updatedAt" = NOW()
        WHERE "userId" = ${userId}
          AND "capability" = ${LIVE_COACH_CAPABILITY}
          AND "periodKey" = ${LIVE_COACH_TRIAL_PERIOD_KEY}
      `;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }
}

const promotionSources = new Set(["promotion", LIVE_COACH_FOUNDING_SOURCE]);

function decision(allowed: boolean, reason: LiveCoachAccessDecision["reason"]): LiveCoachAccessDecision {
  return { capability: "live_coach_dynamic", allowed, reason, paywallAvailable: false };
}
