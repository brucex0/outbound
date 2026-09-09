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
import { phraseForPlan } from "./liveCoachGuidancePlanner.js";
import { transcriptForLiveCoachCue } from "./liveCoachGuidanceText.js";
import { effectiveModeForUser, loadLiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { stableLiveCoachInstructions } from "./liveCoachPrompt.js";
import { LiveCoachSessionService } from "./liveCoachSessionService.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachSessionSnapshot, RequestLiveCoachCueInput } from "./liveCoachTypes.js";

export type LiveCoachStreamMetadata = Omit<LiveCoachCueEnvelope, "audio"> & {
  audio?: {
    contentType: "audio/L16";
    codec: "pcm_s16le";
    sampleRateHz: 24_000;
    channels: 1;
  };
  timing: {
    serverReceivedAtUnixMilliseconds: number;
    providerStartedAtUnixMilliseconds?: number;
  };
};

export type PreparedLiveCoachStream = {
  metadata: LiveCoachStreamMetadata;
  chunks: AsyncIterable<Uint8Array>;
};

export class LiveCoachStreamingService {
  private readonly sessions: LiveCoachSessionService;

  constructor(private readonly prisma: PrismaClient) {
    this.sessions = new LiveCoachSessionService(prisma);
  }

  async prepare(
    userId: string,
    sessionId: string,
    input: RequestLiveCoachCueInput,
    signal: AbortSignal
  ): Promise<PreparedLiveCoachStream> {
    const receivedAt = Date.now();
    if (!liveCoachCueRepository.allowSessionRequest(sessionId)) {
      throw new AIProviderError("rate_limited", "The live-coach session request limit was reached.");
    }
    const session = await this.sessions.ownedActiveSession(userId, sessionId);
    const config = loadLiveCoachFeatureConfig();
    const policy = cuePolicyDecision(input, config);
    if (policy.result || !policy.dynamicEligible) {
      const result = policy.result ?? "success";
      await this.recordFixedCue(session.id, input, session.contextHash, result);
      return fixedStream(session, input, result, receivedAt);
    }
    if (config.mode !== "dynamic"
        || effectiveModeForUser(config, userId) !== "dynamic"
        || session.effectiveMode !== "dynamic"
        || !session.route) {
      const result: LiveCoachCueResult = config.mode === "disabled" ? "feature_disabled" : "unavailable";
      await this.recordFixedCue(session.id, input, session.contextHash, result);
      return fixedStream(session, input, result, receivedAt);
    }

    const accessResolver = new DatabaseLiveCoachEntitlementResolver(this.prisma);
    const access = config.accessMode === "founding_trial" && session.accessReason === "open_beta"
      ? { allowed: true }
      : await accessResolver.resolve(userId, new Date(), config);
    if (!access.allowed) {
      const result: LiveCoachCueResult = "entitlement_required";
      await this.recordFixedCue(session.id, input, session.contextHash, result);
      return fixedStream(session, input, result, receivedAt);
    }

    const reservation = await this.reserveDynamicCue(session, input, config.cueValidityMilliseconds);
    if (reservation !== "reserved") {
      return fixedStream(session, input, reservation, receivedAt);
    }
    if (!liveCoachCueRepository.tryBeginGeneration(session.id, input.cueRequestId)) {
      await this.releaseReservation(session.id, input.cueRequestId, "unavailable");
      return fixedStream(session, input, "unavailable", receivedAt);
    }

    const provider = pinnedProvider(session.route.providerKey, session.route.providerEndpointKey, session.route.providerModel);
    const persona = findCoachPersona(session.coachPersonaId);
    if (!provider?.streamCue || !persona) {
      liveCoachCueRepository.endGeneration(session.id, input.cueRequestId);
      await this.releaseReservation(session.id, input.cueRequestId, "unavailable");
      return fixedStream(session, input, "unavailable", receivedAt);
    }

    const providerStartedAt = Date.now();
    const expiresAt = new Date(receivedAt + input.validForMilliseconds);
    let transcript: string;
    try {
      transcript = exactTranscript(session, input);
    } catch {
      liveCoachCueRepository.endGeneration(session.id, input.cueRequestId);
      await this.releaseReservation(session.id, input.cueRequestId, "invalid");
      return fixedStream(session, input, "invalid", receivedAt);
    }

    try {
      const providerStream = await provider.streamCue({
        requestId: input.cueRequestId,
        locale: session.locale,
        coachPersonaId: persona.id as CoachPersonaId,
        coachPersonaInstructions: persona.instructions,
        voiceProfileId: session.voiceProfileId as VoiceProfileId,
        providerVoice: session.route.providerVoice,
        semanticMoment: input.moment,
        stableInstructions: stableLiveCoachInstructions(session.locale, session.compiledContext.measurementUnitSystem),
        compiledContext: session.compiledContext,
        liveState: input.liveState,
        recentCueSummaries: liveCoachCueRepository.recentCueSummariesForSession(session.id),
        maximumSpokenWordsEquivalent: 36,
        exactTranscript: transcript,
        deadline: new Date(receivedAt + Math.min(config.providerDeadlineMilliseconds, input.validForMilliseconds)),
      }, signal);
      const chunks = this.finalizedChunks(
        providerStream.chunks,
        session,
        input,
        transcript,
        receivedAt,
        accessResolver,
        userId
      );
      return {
        metadata: {
          contractVersion: 1,
          cueRequestId: input.cueRequestId,
          source: "dynamic_generation",
          result: "success",
          moment: input.moment,
          urgency: urgencyForMoment(input.moment),
          transcript,
          audio: { contentType: "audio/L16", codec: "pcm_s16le", sampleRateHz: 24_000, channels: 1 },
          generatedAt: new Date(providerStartedAt).toISOString(),
          expiresAt: expiresAt.toISOString(),
          timing: {
            serverReceivedAtUnixMilliseconds: receivedAt,
            providerStartedAtUnixMilliseconds: providerStartedAt,
          },
        },
        chunks,
      };
    } catch (error) {
      liveCoachCueRepository.endGeneration(session.id, input.cueRequestId);
      const providerError = sanitizedProviderError(error);
      const result = resultForProviderError(providerError.code, expiresAt);
      await this.releaseReservation(session.id, input.cueRequestId, result);
      return fixedStream(session, input, result, receivedAt);
    }
  }

  private async *finalizedChunks(
    source: AsyncIterable<Uint8Array>,
    session: LiveCoachSessionSnapshot,
    input: RequestLiveCoachCueInput,
    transcript: string,
    startedAt: number,
    accessResolver: DatabaseLiveCoachEntitlementResolver,
    userId: string
  ): AsyncIterable<Uint8Array> {
    let byteCount = 0;
    let firstAudioAt: number | null = null;
    try {
      for await (const chunk of source) {
        if (firstAudioAt == null) firstAudioAt = Date.now();
        byteCount += chunk.byteLength;
        yield chunk;
      }
      if (firstAudioAt == null) throw new AIProviderError("invalid_provider_output", "The provider returned no audio.");
      liveCoachCueRepository.appendCueSummary(session.id, transcript);
      await this.prisma.$transaction([
        this.prisma.liveCoachCue.update({
          where: { sessionId_cueRequestId: { sessionId: session.id, cueRequestId: input.cueRequestId } },
          data: {
            resultCategory: "success",
            latencyBucket: latencyBucket(firstAudioAt - startedAt),
            outputAudioBucket: byteBucket(byteCount),
          },
        }),
        // This legacy field is now a per-session success marker, not a cue counter.
        this.prisma.liveCoachSession.update({
          where: { id: session.id },
          data: { dynamicCueCount: 1 },
        }),
      ]);
      if (session.accessReason === "open_beta" && session.dynamicCueCount === 0) {
        await accessResolver.finalizeTrialRun(userId);
      }
    } catch (error) {
      const result = resultForProviderError(sanitizedProviderError(error).code, new Date(startedAt + 5_000));
      await this.releaseReservation(session.id, input.cueRequestId, result).catch(() => undefined);
      throw error;
    } finally {
      liveCoachCueRepository.endGeneration(session.id, input.cueRequestId);
    }
  }

  private async reserveDynamicCue(
    session: LiveCoachSessionSnapshot,
    input: RequestLiveCoachCueInput,
    maximumValidityMilliseconds: number
  ): Promise<"reserved" | "unavailable"> {
    try {
      return await this.prisma.$transaction(async (tx) => {
        const existing = await tx.liveCoachCue.findUnique({
          where: { sessionId_cueRequestId: { sessionId: session.id, cueRequestId: input.cueRequestId } },
        });
        if (existing) return "unavailable" as const;
        await tx.liveCoachCue.create({ data: {
          sessionId: session.id,
          cueRequestId: input.cueRequestId,
          moment: input.moment,
          source: "dynamic_generation",
          resultCategory: "reserved",
          contextHash: session.contextHash,
          expiresAt: new Date(Date.now() + Math.min(input.validForMilliseconds, maximumValidityMilliseconds)),
        } });
        return "reserved" as const;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") return "unavailable";
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
      } });
    } catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002")) throw error;
    }
  }

  private async releaseReservation(sessionId: string, cueRequestId: string, resultCategory: string): Promise<void> {
    await this.prisma.liveCoachCue.update({
      where: { sessionId_cueRequestId: { sessionId, cueRequestId } },
      data: { source: "cached_fallback", resultCategory },
    });
  }
}

function exactTranscript(session: LiveCoachSessionSnapshot, input: RequestLiveCoachCueInput): string {
  if (input.moment === "progress") {
    return transcriptForLiveCoachCue({
      locale: session.locale,
      moment: input.moment,
      liveState: input.liveState,
      cueRequestId: input.cueRequestId,
      measurementUnitSystem: session.compiledContext.measurementUnitSystem,
    });
  }
  if (!input.selectedPhraseId) {
    throw new AIProviderError("invalid_provider_output", "A planned phrase ID is required for this cue.");
  }
  const transcript = phraseForPlan(
    session.guidancePlan,
    input.selectedPhraseId,
    input.moment,
    input.liveState.workoutSegmentPhase
  );
  if (!transcript) throw new AIProviderError("invalid_provider_output", "The selected phrase is not in this session plan.");
  return transcript;
}

function fixedStream(
  session: LiveCoachSessionSnapshot,
  input: RequestLiveCoachCueInput,
  result: LiveCoachCueResult,
  receivedAt: number
): PreparedLiveCoachStream {
  const envelope = fixedFallbackEnvelope({
    cueRequestId: input.cueRequestId,
    moment: input.moment,
    locale: session.locale,
    validForMilliseconds: input.validForMilliseconds,
    result,
    source: result === "success" ? "fixed_pack" : "cached_fallback",
  });
  const { audio: _audio, ...metadata } = envelope;
  return {
    metadata: { ...metadata, timing: { serverReceivedAtUnixMilliseconds: receivedAt } },
    chunks: emptyChunks(),
  };
}

async function* emptyChunks(): AsyncIterable<Uint8Array> {}

function pinnedProvider(providerKey: string, endpointKey: string, model: string): LiveCoachAIProvider | null {
  return buildAIProviderRegistry(loadAIProviderConfiguration()).find((provider) =>
    provider.key === providerKey && provider.endpointKey === endpointKey && provider.model === model
  ) ?? null;
}

function resultForProviderError(code: AIProviderError["code"], expiresAt: Date): LiveCoachCueResult {
  if (Date.now() >= expiresAt.getTime()) return "stale";
  switch (code) {
    case "deadline_exceeded": return "timeout";
    case "invalid_provider_output": return "invalid";
    case "budget_exhausted": return "budget_exhausted";
    default: return "unavailable";
  }
}

function latencyBucket(milliseconds: number): string {
  if (milliseconds < 500) return "under_500ms";
  if (milliseconds < 750) return "500ms_749ms";
  if (milliseconds < 1_000) return "750ms_999ms";
  return "1s_plus";
}

function byteBucket(value: number): string {
  if (value < 64 * 1024) return "under_64k";
  if (value < 128 * 1024) return "64k_127k";
  if (value < 256 * 1024) return "128k_255k";
  return "256k_plus";
}
