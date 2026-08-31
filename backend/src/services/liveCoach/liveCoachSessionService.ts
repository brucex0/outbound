import { Prisma, type LiveCoachSession, type PrismaClient } from "@prisma/client";
import { AIProviderError } from "../aiProviders/errors.js";
import { loadAIProviderConfiguration } from "../aiProviders/config.js";
import { buildAIProviderRegistry } from "../aiProviders/registry.js";
import { resolveAIRoute } from "../aiProviders/router.js";
import type { ResolvedAIRoute, SupportedAILocale } from "../aiProviders/types.js";
import { compileLiveCoachContext } from "./liveCoachContextCompiler.js";
import {
  DatabaseLiveCoachEntitlementResolver,
  LIVE_COACH_CAPABILITY,
  LIVE_COACH_TRIAL_PERIOD_KEY,
} from "./liveCoachAccessPolicy.js";
import { findCoachPersona, findVoiceProfile } from "./liveCoachCatalog.js";
import { effectiveModeForUser, isLiveCoachLocaleEnabled, loadLiveCoachFeatureConfig, type LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { generateLiveCoachGuidancePlan } from "./liveCoachGuidancePlanner.js";
import type { CreateLiveCoachSessionInput, LiveCoachAccessDecision, LiveCoachSessionSnapshot } from "./liveCoachTypes.js";

// Retained only for older clients whose response contract requires a numeric limit.
// Server and current clients do not enforce a per-workout cue quota.
const UNLIMITED_DYNAMIC_CUE_COMPATIBILITY_LIMIT = 1_000_000;

export class LiveCoachSessionService {
  constructor(private readonly prisma: PrismaClient) {}

  async create(userId: string, input: CreateLiveCoachSessionInput) {
    const feature = loadLiveCoachFeatureConfig();
    if (feature.mode === "disabled") throw new AIProviderError("not_eligible", "Server audio coaching is disabled.");
    if (!isLiveCoachLocaleEnabled(feature, input.locale)) {
      throw new AIProviderError("not_eligible", "Server audio coaching is unavailable for the selected language.");
    }
    const existing = await this.prisma.liveCoachSession.findUnique({
      where: { userId_clientSessionId: { userId, clientSessionId: input.clientSessionId } },
    });
    if (existing) return this.createResponse(existing);

    const persona = findCoachPersona(input.coachPersonaId);
    const voice = findVoiceProfile(input.voiceProfileId);
    if (!persona || !voice
        || !feature.enabledPersonaIds.includes(persona.id)
        || !feature.enabledVoiceProfileIds.includes(voice.id)
        || !persona.allowedVoiceProfileIds.includes(voice.id)
        || !voice.supportedLocales.includes(input.locale)) {
      throw new AIProviderError("not_eligible", "The selected coach and voice combination is unavailable.");
    }

    const compiled = await compileLiveCoachContext(
      this.prisma,
      userId,
      input
    );
    const accessResolver = new DatabaseLiveCoachEntitlementResolver(this.prisma);
    let access = await accessResolver.resolve(userId, new Date(), feature);
    const requestedMode = effectiveModeForUser(feature, userId);
    let effectiveMode = requestedMode === "dynamic"
        && access.allowed
        && input.coachingContract !== "quiet"
        && !compiled.context.safetyRequiresFixedOnly
      ? "dynamic" as const
      : "fixed_only" as const;
    let route: ResolvedAIRoute | null = null;
    if (effectiveMode === "dynamic") {
      try {
        const providerConfig = loadAIProviderConfiguration();
        route = resolveAIRoute(buildAIProviderRegistry(providerConfig), {
          requestKind: "live_coach_dynamic",
          market: "global",
          locale: input.locale,
          voiceProfileId: voice.id,
          requiredCapabilities: ["audio_output"],
          deploymentRegion: feature.deploymentRegion,
          latencyClass: "interactive",
        }, providerConfig.routePolicyVersion).route;
      } catch {
        effectiveMode = "fixed_only";
      }
    }

    let trialReserved = false;
    if (effectiveMode === "dynamic" && feature.accessMode === "founding_trial" && access.reason === "open_beta") {
      trialReserved = await accessResolver.reserveTrialRun(userId, feature);
      if (!trialReserved) {
        access = {
          capability: "live_coach_dynamic",
          allowed: false,
          reason: "entitlement_required",
          paywallAvailable: false,
        };
        effectiveMode = "fixed_only";
        route = null;
      }
    }

    const expiresAt = new Date(Date.now() + 4 * 60 * 60 * 1_000);
    const planned = await generateLiveCoachGuidancePlan(compiled.context, persona.id, {
      ...feature,
      planner: { ...feature.planner, enabled: feature.planner.enabled && effectiveMode === "dynamic" },
    });
    let session: LiveCoachSession;
    try {
      session = await this.prisma.liveCoachSession.create({ data: {
        userId,
        clientSessionId: input.clientSessionId,
        workoutId: input.workoutId,
        status: "active",
        locale: input.locale,
        market: "global",
        coachPersonaId: persona.id,
        personaVersion: persona.instructionVersion,
        voiceProfileId: voice.id,
        coachingContract: input.coachingContract,
        effectiveAudioMode: effectiveMode,
        configVersion: feature.configVersion,
        accessReason: access.reason,
        providerKey: route?.providerKey,
        providerEndpointKey: route?.providerEndpointKey,
        providerModel: route?.providerModel,
        providerVoice: route?.providerVoice,
        routePolicyVersion: route?.routePolicyVersion,
        compiledContext: compiled.context as unknown as Prisma.InputJsonValue,
        contextHash: compiled.contextHash,
        contextVersion: 2,
        guidancePlan: planned.plan as unknown as Prisma.InputJsonValue,
        guidancePlanHash: planned.planHash,
        plannerStatus: planned.status,
        plannerModel: planned.model,
        plannerPromptVersion: planned.promptVersion,
        dynamicCueLimit: UNLIMITED_DYNAMIC_CUE_COMPATIBILITY_LIMIT,
        expiresAt,
      }});
    } catch (error) {
      if (trialReserved) await accessResolver.releaseTrialRun(userId).catch(() => undefined);
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        session = await this.prisma.liveCoachSession.findUniqueOrThrow({
          where: { userId_clientSessionId: { userId, clientSessionId: input.clientSessionId } },
        });
      } else {
        throw error;
      }
    }
    return this.createResponse(session, feature, access);
  }

  async ownedActiveSession(userId: string, sessionId: string): Promise<LiveCoachSessionSnapshot> {
    const session = await this.prisma.liveCoachSession.findFirst({ where: { id: sessionId, userId } });
    if (!session) throw new AIProviderError("not_eligible", "Live-coach session was not found.");
    if (session.status !== "active" || session.expiresAt <= new Date()) {
      throw new AIProviderError("not_eligible", "Live-coach session is no longer active.");
    }
    return snapshotFromRow(session);
  }

  async end(userId: string, sessionId: string, outcome: "completed" | "discarded" | "interrupted"): Promise<void> {
    const session = await this.prisma.liveCoachSession.findFirst({ where: { id: sessionId, userId } });
    if (!session) throw new AIProviderError("not_eligible", "Live-coach session was not found.");
    if (session.status !== "active") return;
    await this.prisma.$transaction(async (tx) => {
      const ended = await tx.liveCoachSession.updateMany({
        where: { id: session.id, status: "active" },
        data: { status: outcome, endedAt: new Date() },
      });
      if (ended.count === 0
          || session.accessReason !== "open_beta"
          || session.effectiveAudioMode !== "dynamic") return;
      await tx.featureUsagePeriod.updateMany({
        where: {
          userId,
          capability: LIVE_COACH_CAPABILITY,
          periodKey: LIVE_COACH_TRIAL_PERIOD_KEY,
          reservedCount: { gt: 0 },
        },
        data: {
          reservedCount: { decrement: 1 },
          ...(session.dynamicCueCount > 0 ? { successfulCount: { increment: 1 } } : {}),
        },
      });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  private createResponse(
    session: LiveCoachSession,
    feature = loadLiveCoachFeatureConfig(),
    access?: LiveCoachAccessDecision
  ) {
    const resolvedAccess = access ?? accessFromSession(session);
    return {
      contractVersion: 1,
      sessionId: session.id,
      contextVersion: session.contextVersion,
      expiresAt: session.expiresAt.toISOString(),
      effectiveMode: session.effectiveAudioMode,
      dynamicCoachingAvailable: session.effectiveAudioMode === "dynamic",
      access: {
        dynamicCoaching: resolvedAccess.allowed ? "allowed" : "unavailable",
        reason: resolvedAccess.reason,
        paywallAvailable: false,
      },
      audioPack: {
        manifestVersion: feature.catalogVersion,
        manifestUrl: feature.audioManifestUrl,
      },
      limits: {
        cueValidityMilliseconds: feature.cueValidityMilliseconds,
        maximumDynamicCues: UNLIMITED_DYNAMIC_CUE_COMPATIBILITY_LIMIT,
      },
      guidancePlan: session.guidancePlan,
      guidancePlanHash: session.guidancePlanHash,
      planner: {
        status: session.plannerStatus,
        model: session.plannerModel,
        promptVersion: session.plannerPromptVersion,
      },
    };
  }
}

function snapshotFromRow(session: LiveCoachSession): LiveCoachSessionSnapshot {
  const route = session.providerKey && session.providerEndpointKey && session.providerModel
    && session.providerVoice && session.routePolicyVersion ? {
      providerKey: session.providerKey as ResolvedAIRoute["providerKey"],
      providerEndpointKey: session.providerEndpointKey,
      providerModel: session.providerModel,
      providerVoice: session.providerVoice,
      routePolicyVersion: session.routePolicyVersion,
    } : null;
  return {
    id: session.id,
    userId: session.userId,
    locale: session.locale as SupportedAILocale,
    coachPersonaId: session.coachPersonaId,
    personaVersion: session.personaVersion,
    voiceProfileId: session.voiceProfileId,
    coachingContract: session.coachingContract as LiveCoachSessionSnapshot["coachingContract"],
    accessReason: session.accessReason as LiveCoachSessionSnapshot["accessReason"],
    effectiveMode: session.effectiveAudioMode as LiveCoachSessionSnapshot["effectiveMode"],
    compiledContext: session.compiledContext as unknown as LiveCoachSessionSnapshot["compiledContext"],
    contextHash: session.contextHash,
    guidancePlan: session.guidancePlan as unknown as LiveCoachSessionSnapshot["guidancePlan"],
    guidancePlanHash: session.guidancePlanHash,
    plannerStatus: session.plannerStatus as LiveCoachSessionSnapshot["plannerStatus"],
    plannerModel: session.plannerModel,
    plannerPromptVersion: session.plannerPromptVersion,
    dynamicCueLimit: session.dynamicCueLimit,
    dynamicCueCount: session.dynamicCueCount,
    expiresAt: session.expiresAt,
    route,
  };
}

function accessFromSession(session: LiveCoachSession): LiveCoachAccessDecision {
  const reason = session.accessReason as LiveCoachAccessDecision["reason"];
  return {
    capability: "live_coach_dynamic",
    allowed: ["open_beta", "verified_subscription", "promotion"].includes(reason),
    reason,
    paywallAvailable: false,
  };
}
