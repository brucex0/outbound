import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { Prisma } from "@prisma/client";
import type { AppEnv } from "../types/hono.js";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  auditRewardAdminAction,
  grantAdminPlus,
  issueAdminEntitlementCode,
  rewardsAdmin,
  rewardsAdminMiddleware,
} from "../services/rewardsAdmin.js";
import { featureControlSummary, PAYWALL_FEATURE_CONTROL } from "../services/featureControls.js";

const router = new Hono<AppEnv>();
router.use("*", async (c, next) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  return rewardsAdminMiddleware(c, next);
});

const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
}).passthrough();
const codeListSchema = paginationSchema.extend({
  status: z.enum(["active", "revoked", "all"]).default("all"),
  query: z.string().trim().max(100).optional(),
});
const issueCodeSchema = z.object({
  label: z.string().trim().min(1).max(100),
  durationDays: z.number().int().min(1).max(3_650),
  maxRedemptions: z.number().int().min(1).max(100_000).default(1),
  expiresAt: z.string().datetime().nullable().optional(),
  reason: z.string().trim().min(1).max(500),
}).strict();
const mutationReasonSchema = z.object({ reason: z.string().trim().min(1).max(500) }).strict();
const updateCodeSchema = z.object({
  label: z.string().trim().min(1).max(100).optional(),
  maxRedemptions: z.number().int().min(1).max(100_000).optional(),
  expiresAt: z.string().datetime().nullable().optional(),
  reason: z.string().trim().min(1).max(500),
}).strict().refine((body) => body.label !== undefined || body.maxRedemptions !== undefined || body.expiresAt !== undefined,
  { message: "At least one code field must be updated." });
const userListSchema = paginationSchema.extend({ query: z.string().trim().min(1).max(100).optional() });
const referralListSchema = paginationSchema.extend({ status: z.enum(["claimed", "rewarded", "all"]).default("all") });
const grantSchema = z.object({
  durationDays: z.number().int().min(1).max(3_650).nullable(),
  reason: z.string().trim().min(1).max(500),
}).strict();
const featureControlSchema = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().min(1).max(500),
}).strict();
const telemetrySchema = z.object({
  event: z.enum(["portal_loaded", "section_viewed", "search_performed", "mutation_result"]),
  section: z.enum(["home", "rewards", "dashboard", "controls", "codes", "redemptions", "referrals", "users", "audit"]).optional(),
  operation: z.enum(["code_issue", "code_update", "code_revoke", "code_activate", "plus_grant", "entitlement_revoke", "paywall_control_update"]).optional(),
  result: z.enum(["success", "failure"]).optional(),
}).strict().superRefine((value, context) => {
  if (value.event === "mutation_result" && (!value.operation || !value.result)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "Mutation telemetry requires operation and result." });
  }
  if (value.event !== "mutation_result" && !value.section) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: "Navigation telemetry requires section." });
  }
});

router.get("/me", async (c) => {
  const actor = rewardsAdmin(c);
  return c.json({ id: actor.id, email: actor.normalizedEmail, displayName: actor.displayName });
});

router.post("/telemetry", zValidator("json", telemetrySchema), async (c) => {
  // Bounded operational data only: never add actor, user, code, label, reason, or timestamp fields here.
  console.info("[rewards-admin] portal event", c.req.valid("json"));
  return c.body(null, 204);
});

router.get("/summary", async (c) => {
  const prisma = getPrismaClient();
  const now = new Date();
  const [activeCodes, totalRedemptions, activeEntitlements, pendingReferrals, rewardedReferrals, users] = await Promise.all([
    prisma.entitlementCode.count({ where: { status: "active", OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] } }),
    prisma.entitlementCodeRedemption.count(),
    prisma.featureEntitlement.count({ where: { status: "active", startsAt: { lte: now }, OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] } }),
    prisma.referralClaim.count({ where: { status: "claimed" } }),
    prisma.referralClaim.count({ where: { status: "rewarded" } }),
    prisma.user.count(),
  ]);
  return c.json({ activeCodes, totalRedemptions, activeEntitlements, pendingReferrals, rewardedReferrals, users });
});

router.get("/feature-controls", async (c) => {
  return c.json(await featureControlSummary(getPrismaClient()));
});

router.put("/feature-controls/paywall", zValidator("json", featureControlSchema), async (c) => {
  const body = c.req.valid("json");
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const control = await prisma.$transaction(async (tx) => {
    const updated = await tx.featureControl.upsert({
      where: { key: PAYWALL_FEATURE_CONTROL },
      update: { enabled: body.enabled },
      create: { key: PAYWALL_FEATURE_CONTROL, enabled: body.enabled },
    });
    await auditRewardAdminAction(tx, actor, {
      action: "feature_control_updated",
      targetType: "feature_control",
      targetId: PAYWALL_FEATURE_CONTROL,
      reason: body.reason,
      metadata: { enabled: body.enabled },
    });
    return updated;
  });
  return c.json({ paywallEnabled: control.enabled, updatedAt: control.updatedAt });
});

router.get("/codes", zValidator("query", codeListSchema), async (c) => {
  const { limit, offset, status, query } = c.req.valid("query");
  const where: Prisma.EntitlementCodeWhereInput = {
    ...(status === "all" ? {} : { status }),
    ...(query ? { label: { contains: query, mode: "insensitive" } } : {}),
  };
  const prisma = getPrismaClient();
  const [items, total] = await Promise.all([
    prisma.entitlementCode.findMany({ where, orderBy: { createdAt: "desc" }, skip: offset, take: limit,
      select: { id: true, label: true, bundle: true, durationDays: true, maxRedemptions: true, redemptionCount: true, status: true, expiresAt: true, createdAt: true, updatedAt: true } }),
    prisma.entitlementCode.count({ where }),
  ]);
  return c.json({ items, total, limit, offset });
});

router.post("/codes", zValidator("json", issueCodeSchema), async (c) => {
  const body = c.req.valid("json");
  const expiresAt = body.expiresAt ? new Date(body.expiresAt) : null;
  if (expiresAt && expiresAt <= new Date()) return c.json({ error: "Expiration must be in the future.", code: "invalid_expiration" }, 422);
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const result = await prisma.$transaction(async (tx) => {
    const issued = await issueAdminEntitlementCode(tx, { ...body, expiresAt });
    await auditRewardAdminAction(tx, actor, { action: "entitlement_code_issued", targetType: "entitlement_code", targetId: issued.record.id,
      reason: body.reason, metadata: { label: body.label, durationDays: body.durationDays, maxRedemptions: body.maxRedemptions, expiresAt: body.expiresAt ?? null } });
    return issued;
  });
  return c.json({ code: result.code, item: codeResponse(result.record) }, 201);
});

router.patch("/codes/:id", zValidator("json", updateCodeSchema), async (c) => {
  const id = c.req.param("id");
  const body = c.req.valid("json");
  const expiresAt = body.expiresAt === undefined ? undefined : body.expiresAt === null ? null : new Date(body.expiresAt);
  if (expiresAt && expiresAt <= new Date()) return c.json({ error: "Expiration must be in the future.", code: "invalid_expiration" }, 422);
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const result = await prisma.$transaction(async (tx) => {
    const code = await tx.entitlementCode.findUnique({ where: { id } });
    if (!code) return null;
    if (body.maxRedemptions !== undefined && body.maxRedemptions < code.redemptionCount) {
      return "redemption_limit_too_low" as const;
    }
    const updated = await tx.entitlementCode.update({ where: { id }, data: {
      ...(body.label !== undefined ? { label: body.label } : {}),
      ...(body.maxRedemptions !== undefined ? { maxRedemptions: body.maxRedemptions } : {}),
      ...(expiresAt !== undefined ? { expiresAt } : {}),
    } });
    await auditRewardAdminAction(tx, actor, { action: "entitlement_code_updated", targetType: "entitlement_code", targetId: id,
      reason: body.reason, metadata: { labelChanged: body.label !== undefined, maxRedemptions: body.maxRedemptions, expiresAt: body.expiresAt } });
    return updated;
  });
  if (!result) return c.json({ error: "Code not found.", code: "code_not_found" }, 404);
  if (result === "redemption_limit_too_low") return c.json({ error: "Redemption limit cannot be below current usage.", code: result }, 422);
  return c.json(codeResponse(result));
});

router.post("/codes/:id/revoke", zValidator("json", mutationReasonSchema), async (c) => {
  return setCodeStatus(c, "revoked");
});

router.post("/codes/:id/activate", zValidator("json", mutationReasonSchema), async (c) => {
  return setCodeStatus(c, "active");
});

router.get("/redemptions", zValidator("query", paginationSchema.extend({ codeId: z.string().optional(), userId: z.string().optional() })), async (c) => {
  const { limit, offset, codeId, userId } = c.req.valid("query");
  const where: Prisma.EntitlementCodeRedemptionWhereInput = { ...(codeId ? { codeId } : {}), ...(userId ? { userId } : {}) };
  const prisma = getPrismaClient();
  const [items, total] = await Promise.all([
    prisma.entitlementCodeRedemption.findMany({ where, orderBy: { createdAt: "desc" }, skip: offset, take: limit,
      select: { id: true, codeId: true, userId: true, createdAt: true, code: { select: { label: true, durationDays: true } },
        user: { select: { username: true, displayName: true, normalizedEmail: true } } } }),
    prisma.entitlementCodeRedemption.count({ where }),
  ]);
  return c.json({ items, total, limit, offset });
});

router.get("/referrals", zValidator("query", referralListSchema), async (c) => {
  const { limit, offset, status } = c.req.valid("query");
  const where: Prisma.ReferralClaimWhereInput = status === "all" ? {} : { status };
  const prisma = getPrismaClient();
  const [items, total] = await Promise.all([
    prisma.referralClaim.findMany({ where, orderBy: { claimedAt: "desc" }, skip: offset, take: limit,
      select: { id: true, status: true, rewardDays: true, claimedAt: true, qualifiedAt: true, rewardedAt: true,
        claimant: { select: { id: true, username: true, displayName: true, normalizedEmail: true } },
        referralLink: { select: { creator: { select: { id: true, username: true, displayName: true, normalizedEmail: true } } } } } }),
    prisma.referralClaim.count({ where }),
  ]);
  return c.json({ items, total, limit, offset });
});

router.get("/users", zValidator("query", userListSchema), async (c) => {
  const { limit, offset, query } = c.req.valid("query");
  const where: Prisma.UserWhereInput = query ? { OR: [
    { username: { contains: query, mode: "insensitive" } },
    { displayName: { contains: query, mode: "insensitive" } },
    { normalizedEmail: { contains: query.toLowerCase(), mode: "insensitive" } },
  ] } : {};
  const prisma = getPrismaClient();
  const [items, total] = await Promise.all([
    prisma.user.findMany({ where, orderBy: { createdAt: "desc" }, skip: offset, take: limit,
      select: { id: true, username: true, displayName: true, normalizedEmail: true, createdAt: true,
        _count: { select: { featureEntitlements: true, entitlementCodeRedemptions: true } } } }),
    prisma.user.count({ where }),
  ]);
  return c.json({ items, total, limit, offset });
});

router.get("/users/:id", async (c) => {
  const user = await getPrismaClient().user.findUnique({ where: { id: c.req.param("id") },
    select: { id: true, username: true, displayName: true, normalizedEmail: true, createdAt: true,
      featureEntitlements: { orderBy: { createdAt: "desc" }, select: { id: true, capability: true, source: true, status: true, startsAt: true, expiresAt: true, createdAt: true, updatedAt: true } },
      entitlementGrantLedger: { orderBy: { createdAt: "desc" }, take: 100, select: { id: true, capability: true, source: true, durationDays: true, startsAt: true, expiresAt: true, revokedAt: true, createdAt: true } },
      entitlementCodeRedemptions: { orderBy: { createdAt: "desc" }, include: { code: { select: { id: true, label: true, durationDays: true } } } },
      referralClaim: { include: { referralLink: { select: { creatorId: true } } } },
      referralLink: { select: { code: true, claimCount: true } },
    } });
  return user ? c.json(user) : c.json({ error: "User not found.", code: "user_not_found" }, 404);
});

router.post("/users/:id/grants", zValidator("json", grantSchema), async (c) => {
  const userId = c.req.param("id");
  const body = c.req.valid("json");
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const exists = await prisma.user.count({ where: { id: userId } });
  if (!exists) return c.json({ error: "User not found.", code: "user_not_found" }, 404);
  const grant = await prisma.$transaction(async (tx) => {
    const created = await grantAdminPlus(tx, userId, body);
    await auditRewardAdminAction(tx, actor, { action: "plus_granted", targetType: "user", targetId: userId,
      reason: body.reason, metadata: { durationDays: body.durationDays, reference: created.reference } });
    return created;
  });
  return c.json({ reference: grant.reference, expiresAt: grant.expiresAt, entitlements: grant.entitlements }, 201);
});

router.post("/users/:userId/entitlements/:entitlementId/revoke", zValidator("json", mutationReasonSchema), async (c) => {
  const { userId, entitlementId } = c.req.param();
  const { reason } = c.req.valid("json");
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const result = await prisma.$transaction(async (tx) => {
    const entitlement = await tx.featureEntitlement.findFirst({ where: { id: entitlementId, userId } });
    if (!entitlement) return null;
    const now = new Date();
    const updated = await tx.featureEntitlement.update({ where: { id: entitlement.id }, data: { status: "revoked", expiresAt: now } });
    if (entitlement.sourceReferenceHash) {
      await tx.entitlementGrantLedger.updateMany({ where: { sourceReferenceHash: entitlement.sourceReferenceHash, revokedAt: null }, data: { revokedAt: now } });
    }
    await auditRewardAdminAction(tx, actor, { action: "entitlement_revoked", targetType: "feature_entitlement", targetId: entitlement.id,
      reason, metadata: { userId, capability: entitlement.capability, source: entitlement.source } });
    return updated;
  });
  return result ? c.json(result) : c.json({ error: "Entitlement not found.", code: "entitlement_not_found" }, 404);
});

router.get("/audit", zValidator("query", paginationSchema.extend({ actorUserId: z.string().optional(), targetType: z.string().max(100).optional(), targetId: z.string().optional() })), async (c) => {
  const { limit, offset, actorUserId, targetType, targetId } = c.req.valid("query");
  const where: Prisma.AdminRewardAuditEventWhereInput = {
    ...(actorUserId ? { actorUserId } : {}), ...(targetType ? { targetType } : {}), ...(targetId ? { targetId } : {}),
  };
  const prisma = getPrismaClient();
  const [items, total] = await Promise.all([
    prisma.adminRewardAuditEvent.findMany({ where, orderBy: { createdAt: "desc" }, skip: offset, take: limit,
      include: { actor: { select: { displayName: true, normalizedEmail: true } } } }),
    prisma.adminRewardAuditEvent.count({ where }),
  ]);
  return c.json({ items, total, limit, offset });
});

async function setCodeStatus(c: any, status: "active" | "revoked") {
  const id = c.req.param("id");
  const { reason } = c.req.valid("json");
  const prisma = getPrismaClient();
  const actor = rewardsAdmin(c);
  const result = await prisma.$transaction(async (tx) => {
    const code = await tx.entitlementCode.findUnique({ where: { id } });
    if (!code) return null;
    if (status === "active" && code.expiresAt && code.expiresAt <= new Date()) return "code_expired" as const;
    const updated = await tx.entitlementCode.update({ where: { id }, data: { status } });
    await auditRewardAdminAction(tx, actor, { action: status === "active" ? "entitlement_code_activated" : "entitlement_code_revoked",
      targetType: "entitlement_code", targetId: id, reason, metadata: { label: code.label } });
    return updated;
  });
  if (!result) return c.json({ error: "Code not found.", code: "code_not_found" }, 404);
  if (result === "code_expired") return c.json({ error: "Expired codes cannot be activated.", code: result }, 422);
  return c.json(codeResponse(result));
}

function codeResponse(code: { id: string; label: string; bundle: string; durationDays: number; maxRedemptions: number; redemptionCount: number; status: string; expiresAt: Date | null; createdAt: Date; updatedAt: Date }) {
  return { id: code.id, label: code.label, bundle: code.bundle, durationDays: code.durationDays,
    maxRedemptions: code.maxRedemptions, redemptionCount: code.redemptionCount, status: code.status,
    expiresAt: code.expiresAt, createdAt: code.createdAt, updatedAt: code.updatedAt };
}

export default router;
