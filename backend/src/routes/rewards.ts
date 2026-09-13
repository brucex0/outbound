import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { AppEnv } from "../types/hono.js";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  claimReferral,
  bankedPlusDays,
  ensurePersonalReferralCode,
  entitlementSummary,
  redeemEntitlementCode,
  RewardCodeError,
  referralProgramForUser,
} from "../services/entitlements.js";
import {
  reconcileRevenueCatPlus,
  RevenueCatConfigurationError,
  RevenueCatUpstreamError,
} from "../services/revenueCat.js";

const router = new Hono<AppEnv>();
const codeSchema = z.object({ code: z.string().trim().min(6).max(64) }).strict();

router.get("/", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  const prisma = getPrismaClient();
  const [referralCode, entitlements, claim, qualifiedCount, pendingCount, referralProgram, bankedRewardDays] = await Promise.all([
    ensurePersonalReferralCode(prisma, user.id),
    entitlementSummary(prisma, user.id),
    prisma.referralClaim.findUnique({ where: { claimantId: user.id }, select: { status: true } }),
    prisma.referralClaim.count({ where: { referralLink: { creatorId: user.id }, status: "rewarded" } }),
    prisma.referralClaim.count({ where: { referralLink: { creatorId: user.id }, status: "claimed" } }),
    referralProgramForUser(prisma, user.id),
    bankedPlusDays(prisma, user.id),
  ]);
  return c.json({
    referral: {
      code: referralCode,
      shareURL: `https://run.plainstride.com/invite/r/${referralCode}`,
      claimStatus: claim?.status ?? null,
      qualifiedCount,
      pendingCount,
    },
    referralProgram,
    bankedRewardDays,
    entitlements,
  });
});

router.post("/referrals/claim", zValidator("json", codeSchema), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  try {
    const claim = await claimReferral(getPrismaClient(), user.id, c.req.valid("json").code);
    return c.json({ claimed: true, rewardDays: claim.inviteeRewardDays });
  } catch (error) { return rewardError(c, error); }
});

router.post("/codes/redeem", zValidator("json", codeSchema), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  try {
    const result = await redeemEntitlementCode(getPrismaClient(), user.id, c.req.valid("json").code);
    return c.json({ redeemed: true, ...result });
  } catch (error) { return rewardError(c, error); }
});

router.post("/subscription/reconcile", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  try {
    const subscription = await reconcileRevenueCatPlus(getPrismaClient(), user.id);
    return c.json({ reconciled: true, active: subscription.active, expiresAt: subscription.expiresAt });
  } catch (error) {
    if (error instanceof RevenueCatConfigurationError) {
      return c.json({ error: "Subscriptions are not configured.", code: "subscription_not_configured" }, 503);
    }
    if (error instanceof RevenueCatUpstreamError) {
      return c.json({ error: "Subscription status is temporarily unavailable.", code: "subscription_unavailable" }, 502);
    }
    throw error;
  }
});

function rewardError(c: any, error: unknown) {
  if (!(error instanceof RewardCodeError)) throw error;
  const status = error.code.includes("already") ? 409 : 422;
  return c.json({ error: "This code cannot be redeemed.", code: error.code }, status);
}

export default router;
