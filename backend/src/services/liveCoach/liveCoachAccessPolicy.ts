import type { PrismaClient } from "@prisma/client";
import type { LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import type { LiveCoachAccessDecision } from "./liveCoachTypes.js";

export interface LiveCoachEntitlementResolver {
  resolve(userId: string, now: Date, config: LiveCoachFeatureConfig): Promise<LiveCoachAccessDecision>;
}

export class DatabaseLiveCoachEntitlementResolver implements LiveCoachEntitlementResolver {
  constructor(private readonly prisma: PrismaClient) {}

  async resolve(userId: string, now: Date, config: LiveCoachFeatureConfig): Promise<LiveCoachAccessDecision> {
    if (config.mode !== "dynamic") return decision(false, "feature_disabled");
    if (config.accessMode === "open_beta") return decision(true, "open_beta");
    const entitlement = await this.prisma.featureEntitlement.findFirst({
      where: {
        userId,
        capability: "live_coach_dynamic",
        status: "active",
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: "desc" },
    });
    if (!entitlement) return decision(false, "entitlement_required");
    return decision(true, entitlement.source === "promotion" ? "promotion" : "verified_subscription");
  }
}

function decision(allowed: boolean, reason: LiveCoachAccessDecision["reason"]): LiveCoachAccessDecision {
  return { capability: "live_coach_dynamic", allowed, reason, paywallAvailable: false };
}
