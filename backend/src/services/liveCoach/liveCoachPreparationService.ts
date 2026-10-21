import { createHash } from "node:crypto";
import { Prisma, type PrismaClient } from "@prisma/client";
import type { LiveCoachCompiledContext } from "../aiProviders/types.js";
import { AIProviderError } from "../aiProviders/errors.js";
import { compileLiveCoachContext } from "./liveCoachContextCompiler.js";
import { DatabaseLiveCoachEntitlementResolver } from "./liveCoachAccessPolicy.js";
import { findCoachPersona, findVoiceProfile } from "./liveCoachCatalog.js";
import { effectiveModeForUser, isLiveCoachLocaleEnabled, loadLiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { generateLiveCoachGuidancePlan, LIVE_COACH_PLANNER_PROMPT_VERSION, type GuidancePlannerResult } from "./liveCoachGuidancePlanner.js";
import type { CreateLiveCoachSessionInput } from "./liveCoachTypes.js";

type Compiled = Awaited<ReturnType<typeof compileLiveCoachContext>>;
const lifetimeMilliseconds = 15 * 60_000;

export class LiveCoachPreparationService {
  constructor(private readonly prisma: PrismaClient) {}

  async prepare(userId: string, input: CreateLiveCoachSessionInput, compiled?: Compiled, validatedSessionAccess = false) {
    const feature = loadLiveCoachFeatureConfig();
    const persona = findCoachPersona(input.coachPersonaId);
    const voice = findVoiceProfile(input.voiceProfileId);
    const accessAllowed = validatedSessionAccess || (await new DatabaseLiveCoachEntitlementResolver(this.prisma).resolve(userId, new Date(), feature)).allowed;
    if (!feature.planner.enabled || effectiveModeForUser(feature, userId) !== "dynamic" || !accessAllowed
        || input.sessionIntent.activityType !== "running" || input.coachingContract === "quiet"
        || !isLiveCoachLocaleEnabled(feature, input.locale) || !persona || !voice
        || !feature.enabledPersonaIds.includes(persona.id) || !feature.enabledVoiceProfileIds.includes(voice.id)
        || !persona.allowedVoiceProfileIds.includes(voice.id) || !voice.supportedLocales.includes(input.locale)) {
      throw new AIProviderError("not_eligible", "Coaching preparation is unavailable.");
    }
    const context = compiled ?? await compileLiveCoachContext(this.prisma, userId, input);
    if (context.context.safetyRequiresFixedOnly) throw new AIProviderError("not_eligible", "Coaching preparation requires fixed guidance.");
    const cacheKey = createHash("sha256").update(JSON.stringify([
      userId, context.contextHash, input.coachPersonaId, persona.instructionVersion, input.voiceProfileId,
      input.coachingContract, feature.configVersion, feature.planner.model, LIVE_COACH_PLANNER_PROMPT_VERSION,
      process.env.AI_FALLBACK_VALIDATED, process.env.AI_FALLBACK_MODEL,
    ])).digest("hex");
    await this.prisma.liveCoachPreparation.deleteMany({ where: { userId, expiresAt: { lte: new Date() } } });
    const existing = await this.prisma.liveCoachPreparation.findUnique({ where: { cacheKey } });
    if (existing) { console.info("live_coach_preparation", { operation: "prepare", result: "cache_hit" }); return existing; }
    if (await this.prisma.liveCoachPreparation.count({ where: { userId } }) >= 6) {
      const oldest = await this.prisma.liveCoachPreparation.findFirst({
        where: { userId, status: { not: "generating" } }, orderBy: { createdAt: "asc" }, select: { id: true },
      });
      if (!oldest) throw new AIProviderError("rate_limited", "Too many coaching preparations.");
      await this.prisma.liveCoachPreparation.deleteMany({ where: { id: oldest.id, userId, status: { not: "generating" } } });
    }
    const row = await this.prisma.liveCoachPreparation.upsert({
      where: { cacheKey }, update: {}, create: {
        userId, cacheKey, contextHash: context.contextHash,
        compiledContext: context.context as unknown as Prisma.InputJsonValue,
        coachPersonaId: input.coachPersonaId, expiresAt: new Date(Date.now() + lifetimeMilliseconds),
      },
    });
    console.info("live_coach_preparation", { operation: "prepare", result: "pending" });
    return row;
  }

  async owned(userId: string, id: string) {
    const row = await this.prisma.liveCoachPreparation.findFirst({ where: { id, userId, expiresAt: { gt: new Date() } } });
    if (!row) throw new AIProviderError("not_eligible", "Coaching preparation expired or is unavailable.");
    return row;
  }

  // This work stays inside an awaited HTTP request, never detached from Cloud Run.
  async generate(userId: string, id: string) {
    await this.prisma.liveCoachPreparation.updateMany({ where: {
      id, userId, status: "generating", generationStartedAt: { lt: new Date(Date.now() - 90_000) },
    }, data: { status: "pending", generationStartedAt: null } });
    const row = await this.owned(userId, id);
    if (row.status !== "pending") return row;
    const feature = loadLiveCoachFeatureConfig();
    const access = await new DatabaseLiveCoachEntitlementResolver(this.prisma).resolve(userId, new Date(), feature);
    // Match live streaming: a trial already reserved by this active session may
    // finish planning even when that reservation consumed the last free run.
    const reservedSession = !access.allowed && feature.accessMode === "founding_trial"
      ? await this.prisma.liveCoachSession.findFirst({ where: {
        userId, preparationId: id, status: "active", effectiveAudioMode: "dynamic",
        accessReason: "open_beta", expiresAt: { gt: new Date() },
      }, select: { id: true } }) : null;
    if (!feature.planner.enabled || effectiveModeForUser(feature, userId) !== "dynamic" || (!access.allowed && !reservedSession)) {
      throw new AIProviderError("not_eligible", "Coaching preparation is unavailable.");
    }
    const claimed = await this.prisma.liveCoachPreparation.updateMany({ where: { id, userId, status: "pending" }, data: { status: "generating", generationStartedAt: new Date() } });
    if (!claimed.count) return this.owned(userId, id);
    const startedAt = Date.now();
    try {
      const result = await generateLiveCoachGuidancePlan(row.compiledContext as unknown as LiveCoachCompiledContext, row.coachPersonaId, feature);
      const updated = await this.prisma.liveCoachPreparation.update({ where: { id }, data: {
        status: result.status === "generated" ? "ready" : "fallback",
        ...(result.status === "fallback" ? { expiresAt: new Date(Date.now() + 30_000) } : {}), result: result as unknown as Prisma.InputJsonValue,
      } });
      console.info("live_coach_preparation", { operation: "generate", result: updated.status, latencyBucket: Date.now() - startedAt < 10_000 ? "under_10s" : "10s_or_more" });
      return updated;
    } catch (error) {
      await this.prisma.liveCoachPreparation.updateMany({ where: { id, status: "generating" }, data: { status: "fallback" } });
      console.error("live_coach_preparation", { operation: "generate", result: "failure", errorType: error instanceof Error ? error.name : "unknown" });
      throw error;
    }
  }

  static response(row: { id: string; status: string; expiresAt: Date }) {
    return { contractVersion: 1, preparationId: row.id, status: row.status, expiresAt: row.expiresAt.toISOString() };
  }

  static result(value: Prisma.JsonValue | null): GuidancePlannerResult | null {
    return value ? value as unknown as GuidancePlannerResult : null;
  }
}
