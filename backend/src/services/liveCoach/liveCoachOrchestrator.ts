import { Prisma, type PrismaClient } from "@prisma/client";
import { AIProviderError, sanitizedProviderError } from "../aiProviders/errors.js";
import { loadAIProviderConfiguration } from "../aiProviders/config.js";
import { buildAIProviderRegistry } from "../aiProviders/registry.js";
import type { CoachPersonaId, LiveCoachAIProvider, VoiceProfileId } from "../aiProviders/types.js";
import { DatabaseLiveCoachEntitlementResolver } from "./liveCoachAccessPolicy.js";
import { findCoachPersona } from "./liveCoachCatalog.js";
import { cuePolicyDecision, urgencyForMoment } from "./liveCoachCuePolicy.js";
import { liveCoachCueRepository } from "./liveCoachCueRepository.js";
import { fixedFallbackEnvelope } from "./liveCoachFallback.js";
import { effectiveModeForUser, loadLiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { stableLiveCoachInstructions } from "./liveCoachPrompt.js";
import { LiveCoachSessionService } from "./liveCoachSessionService.js";
import { validateLiveCoachOutput } from "./liveCoachOutputValidation.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, RequestLiveCoachCueInput } from "./liveCoachTypes.js";

export class LiveCoachOrchestrator {
  private readonly sessions: LiveCoachSessionService;

  constructor(private readonly prisma: PrismaClient) {
    this.sessions = new LiveCoachSessionService(prisma);
  }

  requestCue(userId: string, sessionId: string, input: RequestLiveCoachCueInput, requestSignal: AbortSignal) {
    if (!liveCoachCueRepository.allowSessionRequest(sessionId)) {
      throw new AIProviderError("rate_limited", "The live-coach session request limit was reached.");
    }
    return liveCoachCueRepository.runIdempotent(sessionId, input.cueRequestId, (sessionController) =>
      this.performCueRequest(userId, sessionId, input, combineSignals(requestSignal, sessionController.signal))
    );
  }

  private async performCueRequest(
    userId: string,
    sessionId: string,
    input: RequestLiveCoachCueInput,
    signal: AbortSignal
  ): Promise<LiveCoachCueEnvelope> {
    const session = await this.sessions.ownedActiveSession(userId, sessionId);
    const config = loadLiveCoachFeatureConfig();
    const policy = cuePolicyDecision(input, config);
    if (policy.result || !policy.dynamicEligible) {
      const result = policy.result ?? "success";
      await this.recordFixedCue(session.id, input, session.contextHash, result);
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result,
        source: "fixed_pack",
      });
    }

    if (config.mode !== "dynamic"
        || effectiveModeForUser(config, userId) !== "dynamic"
        || session.effectiveMode !== "dynamic"
        || !session.route) {
      const result: LiveCoachCueResult = config.mode === "disabled" ? "feature_disabled" : "unavailable";
      await this.recordFixedCue(session.id, input, session.contextHash, result);
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result,
      });
    }

    const access = await new DatabaseLiveCoachEntitlementResolver(this.prisma).resolve(userId, new Date(), config);
    if (!access.allowed) {
      await this.recordFixedCue(session.id, input, session.contextHash, access.reason === "entitlement_required" ? "entitlement_required" : "unavailable");
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result: access.reason === "entitlement_required" ? "entitlement_required" : "unavailable",
      });
    }

    const reservation = await this.reserveDynamicCue(session.id, input, session.contextHash, config.cueValidityMilliseconds);
    if (reservation === "duplicate") {
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result: "unavailable",
      });
    }
    if (reservation === "quota_exhausted") {
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result: "quota_exhausted",
      });
    }

    const provider = pinnedProvider(session.route.providerKey, session.route.providerEndpointKey, session.route.providerModel);
    const persona = findCoachPersona(session.coachPersonaId);
    if (!provider || !persona) {
      await this.releaseReservation(session.id, input.cueRequestId, "unavailable");
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result: "unavailable",
      });
    }
    if (!liveCoachCueRepository.tryBeginGeneration(session.id, input.cueRequestId)) {
      await this.releaseReservation(session.id, input.cueRequestId, "unavailable");
      return fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: input.validForMilliseconds,
        result: "unavailable",
      });
    }

    const startedAt = Date.now();
    const cueExpiresAt = new Date(startedAt + input.validForMilliseconds);
    try {
      const result = await provider.generateCue({
        requestId: input.cueRequestId,
        locale: session.locale,
        coachPersonaId: persona.id as CoachPersonaId,
        coachPersonaInstructions: persona.instructions,
        voiceProfileId: session.voiceProfileId as VoiceProfileId,
        providerVoice: session.route.providerVoice,
        semanticMoment: input.moment,
        stableInstructions: stableLiveCoachInstructions(session.locale),
        compiledContext: session.compiledContext,
        liveState: input.liveState,
        recentCueSummaries: liveCoachCueRepository.recentCueSummariesForSession(session.id),
        maximumSpokenWordsEquivalent: 18,
        deadline: new Date(startedAt + Math.min(config.providerDeadlineMilliseconds, input.validForMilliseconds)),
      }, signal);
      if (signal.aborted) throw new DOMException("Aborted", "AbortError");
      const transcript = validateLiveCoachOutput(result.transcript);
      const generatedAt = new Date();
      if (generatedAt >= cueExpiresAt) {
        await this.releaseReservation(session.id, input.cueRequestId, "stale");
        return { ...fixedFallbackEnvelope({
          cueRequestId: input.cueRequestId,
          moment: input.moment,
          locale: session.locale,
          validForMilliseconds: 1,
          result: "stale",
        }), expiresAt: cueExpiresAt.toISOString() };
      }
      const envelope: LiveCoachCueEnvelope = {
        contractVersion: 1,
        cueRequestId: input.cueRequestId,
        source: "dynamic_generation",
        result: "success",
        moment: input.moment,
        urgency: urgencyForMoment(input.moment),
        transcript,
        audio: {
          contentType: "audio/wav",
          base64: Buffer.from(result.audio).toString("base64"),
          durationMilliseconds: result.durationMilliseconds,
        },
        generatedAt: generatedAt.toISOString(),
        expiresAt: cueExpiresAt.toISOString(),
      };
      liveCoachCueRepository.appendCueSummary(session.id, transcript);
      await this.finalizeReservation(session.id, input.cueRequestId, {
        resultCategory: "success",
        latencyBucket: latencyBucket(Date.now() - startedAt),
        inputTokenBucket: countBucket(result.usage.inputTokens),
        outputAudioBucket: byteBucket(result.audio.byteLength),
      });
      return envelope;
    } catch (error) {
      const providerError = sanitizedProviderError(error);
      const result = Date.now() >= cueExpiresAt.getTime() ? "stale" : resultForProviderError(providerError.code);
      await this.releaseReservation(session.id, input.cueRequestId, result);
      return { ...fixedFallbackEnvelope({
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        locale: session.locale,
        validForMilliseconds: Math.max(1, cueExpiresAt.getTime() - Date.now()),
        result,
      }), expiresAt: cueExpiresAt.toISOString() };
    } finally {
      liveCoachCueRepository.endGeneration(session.id, input.cueRequestId);
    }
  }

  private async reserveDynamicCue(
    sessionId: string,
    input: RequestLiveCoachCueInput,
    contextHash: string,
    maximumValidityMilliseconds: number
  ): Promise<"reserved" | "duplicate" | "quota_exhausted"> {
    try {
      return await this.prisma.$transaction(async (tx) => {
        const existing = await tx.liveCoachCue.findUnique({
          where: { sessionId_cueRequestId: { sessionId, cueRequestId: input.cueRequestId } },
        });
        if (existing) return "duplicate" as const;
        const session = await tx.liveCoachSession.findUniqueOrThrow({ where: { id: sessionId } });
        if (session.dynamicCueCount >= session.dynamicCueLimit) {
          await tx.liveCoachCue.create({ data: {
            sessionId,
            cueRequestId: input.cueRequestId,
            moment: input.moment,
            source: "cached_fallback",
            resultCategory: "quota_exhausted",
            contextHash,
            expiresAt: new Date(Date.now() + Math.min(input.validForMilliseconds, maximumValidityMilliseconds)),
          }});
          return "quota_exhausted" as const;
        }
        await tx.liveCoachCue.create({ data: {
          sessionId,
          cueRequestId: input.cueRequestId,
          moment: input.moment,
          source: "dynamic_generation",
          resultCategory: "reserved",
          contextHash,
          expiresAt: new Date(Date.now() + Math.min(input.validForMilliseconds, maximumValidityMilliseconds)),
        }});
        await tx.liveCoachSession.update({ where: { id: sessionId }, data: { dynamicCueCount: { increment: 1 } } });
        return "reserved" as const;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") return "duplicate";
      throw error;
    }
  }

  private async recordFixedCue(
    sessionId: string,
    input: RequestLiveCoachCueInput,
    contextHash: string,
    result: LiveCoachCueResult
  ): Promise<void> {
    try {
      await this.prisma.liveCoachCue.create({ data: {
        sessionId,
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        source: result === "success" ? "fixed_pack" : "cached_fallback",
        resultCategory: result,
        contextHash,
        expiresAt: new Date(Date.now() + input.validForMilliseconds),
      }});
    } catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002")) throw error;
    }
  }

  private async finalizeReservation(
    sessionId: string,
    cueRequestId: string,
    data: { resultCategory: string; latencyBucket: string; inputTokenBucket?: string; outputAudioBucket: string }
  ): Promise<void> {
    await this.prisma.liveCoachCue.update({
      where: { sessionId_cueRequestId: { sessionId, cueRequestId } },
      data,
    });
  }

  private async releaseReservation(sessionId: string, cueRequestId: string, resultCategory: string): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.liveCoachCue.update({
        where: { sessionId_cueRequestId: { sessionId, cueRequestId } },
        data: { source: "cached_fallback", resultCategory },
      }),
      this.prisma.liveCoachSession.update({
        where: { id: sessionId },
        data: { dynamicCueCount: { decrement: 1 } },
      }),
    ]);
  }
}

function pinnedProvider(providerKey: string, endpointKey: string, model: string): LiveCoachAIProvider | null {
  return buildAIProviderRegistry(loadAIProviderConfiguration()).find((provider) =>
    provider.key === providerKey && provider.endpointKey === endpointKey && provider.model === model
  ) ?? null;
}

function combineSignals(left: AbortSignal, right: AbortSignal): AbortSignal {
  const controller = new AbortController();
  const abort = () => controller.abort();
  if (left.aborted || right.aborted) controller.abort();
  else {
    left.addEventListener("abort", abort, { once: true });
    right.addEventListener("abort", abort, { once: true });
  }
  return controller.signal;
}

function resultForProviderError(code: AIProviderError["code"]): LiveCoachCueResult {
  switch (code) {
    case "deadline_exceeded": return "timeout";
    case "invalid_provider_output": return "invalid";
    case "budget_exhausted": return "budget_exhausted";
    default: return "unavailable";
  }
}
function latencyBucket(milliseconds: number): string {
  if (milliseconds < 1_000) return "under_1s";
  if (milliseconds < 2_000) return "1s_2s";
  if (milliseconds < 4_000) return "2s_4s";
  return "4s_plus";
}
function countBucket(value: number | undefined): string | undefined {
  if (value == null) return undefined;
  if (value < 250) return "under_250";
  if (value < 500) return "250_499";
  if (value < 1_000) return "500_999";
  return "1000_plus";
}
function byteBucket(value: number): string {
  if (value < 64 * 1024) return "under_64k";
  if (value < 128 * 1024) return "64k_127k";
  if (value < 256 * 1024) return "128k_255k";
  return "256k_plus";
}
