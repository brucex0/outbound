import { Hono, type Context } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import type { AppEnv } from "../types/hono.js";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  agentActionDecisionSchema,
  companionTurnRequestSchema,
  memoryCorrectionSchema,
  memoryForgetSchema,
  situationalSignalInputSchema,
} from "../services/companion/contracts.js";
import { runCompanionTurn } from "../services/companion/companionOrchestrator.js";
import { correctRunnerBelief, forgetRunnerBelief } from "../services/companion/runnerModelProjector.js";
import { decideAndExecuteAgentAction } from "../services/companion/actionExecutor.js";
import { ingestSituationalSignals } from "../services/companion/situationalIntelligence.js";
import { buildSessionBrief } from "../services/companion/sessionBrief.js";

const router = new Hono<AppEnv>();

router.post("/turns", zValidator("json", companionTurnRequestSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json(await runCompanionTurn(getPrismaClient(), user.id, c.req.valid("json"), c.get("locale")));
});

router.get("/snapshot", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const [version, beliefs, pendingActions] = await Promise.all([
    prisma.runnerModelVersion.findFirst({ where: { userId: user.id }, orderBy: { versionNumber: "desc" } }),
    prisma.runnerBelief.findMany({ where: { userId: user.id, status: { not: "forgotten" } }, orderBy: [{ status: "asc" }, { refreshedAt: "desc" }] }),
    prisma.agentAction.findMany({ where: { userId: user.id, status: "proposed" }, orderBy: { createdAt: "desc" }, take: 5 }),
  ]);
  return c.json({ runnerModelVersion: version?.id ?? "runner-model-empty", beliefs: beliefs.map(serializeBelief), pendingActions });
});

router.get("/memories", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const beliefs = await getPrismaClient().runnerBelief.findMany({
    where: { userId: user.id, status: { not: "forgotten" } },
    orderBy: [{ consequenceLevel: "desc" }, { refreshedAt: "desc" }],
  });
  return c.json({ memories: beliefs.map(serializeBelief) });
});

router.put("/memories/:stableKey", zValidator("json", memoryCorrectionSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json({ memory: serializeBelief(await correctRunnerBelief(getPrismaClient(), user.id, c.req.param("stableKey"), c.req.valid("json"))) });
});

router.post("/memories/:stableKey/forget", zValidator("json", memoryForgetSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json({ forgotten: await forgetRunnerBelief(getPrismaClient(), user.id, c.req.param("stableKey"), c.req.valid("json").idempotencyKey) });
});

router.post("/signals", zValidator("json", z.object({ signals: z.array(situationalSignalInputSchema).min(1).max(24) })), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const accepted = await ingestSituationalSignals(getPrismaClient(), user.id, c.req.valid("json").signals);
  return c.json({ accepted: accepted.length });
});

router.post("/actions/:id/decision", zValidator("json", agentActionDecisionSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  try {
    const action = await decideAndExecuteAgentAction(getPrismaClient(), user.id, c.req.param("id"), c.req.valid("json").decision);
    return c.json({ action });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "Unable to apply companion action." }, 409);
  }
});

router.get("/session-brief", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json(await buildSessionBrief(getPrismaClient(), user.id, c.req.query("workoutId")));
});

function serializeBelief(belief: { stableKey: string; kind: string; label: string; value: unknown; summary: string; confidence: number; status: string; source: string; supportingEvidenceIds: string[]; contradictingEvidenceIds: string[]; sensitivity: string; consequenceLevel: string; refreshedAt: Date; expiresAt: Date | null }) {
  return {
    stableKey: belief.stableKey,
    kind: belief.kind,
    label: belief.label,
    value: belief.value,
    summary: belief.summary,
    confidence: belief.confidence,
    status: belief.status,
    source: belief.source,
    evidenceCount: belief.supportingEvidenceIds.length,
    contradictionCount: belief.contradictingEvidenceIds.length,
    sensitivity: belief.sensitivity,
    consequenceLevel: belief.consequenceLevel,
    refreshedAt: belief.refreshedAt.toISOString(),
    expiresAt: belief.expiresAt?.toISOString() ?? null,
  };
}

async function requireUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  return user;
}

export default router;
