import type { PrismaClient } from "@prisma/client";
import { AIProviderError } from "../aiProviders/errors.js";
import { loadAIProviderConfiguration } from "../aiProviders/config.js";
import { buildAIProviderRegistry } from "../aiProviders/registry.js";
import type { CoachPersonaId, LiveCoachAIProvider, VoiceProfileId } from "../aiProviders/types.js";
import { findCoachPersona } from "./liveCoachCatalog.js";
import { liveCoachCueRepository } from "./liveCoachCueRepository.js";
import { loadLiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { stableLiveCoachInstructions } from "./liveCoachPrompt.js";
import { LiveCoachSessionService } from "./liveCoachSessionService.js";
import { phraseForPlan } from "./liveCoachGuidancePlanner.js";
import { DatabaseLiveCoachEntitlementResolver } from "./liveCoachAccessPolicy.js";
import type { RequestLiveCoachCueInput } from "./liveCoachTypes.js";

export class LiveCoachPhraseService {
  private readonly sessions: LiveCoachSessionService;

  constructor(private readonly prisma: PrismaClient) {
    this.sessions = new LiveCoachSessionService(prisma);
  }

  async synthesize(
    userId: string,
    sessionId: string,
    phraseId: string,
    signal: AbortSignal
  ): Promise<{ audio: Uint8Array; transcript: string }> {
    if (!liveCoachCueRepository.allowSessionPrefetch(sessionId)) {
      throw new AIProviderError("rate_limited", "The live-coach phrase prefetch limit was reached.");
    }
    const session = await this.sessions.ownedActiveSession(userId, sessionId);
    if (session.effectiveMode !== "dynamic" || !session.route) {
      throw new AIProviderError("not_eligible", "Dynamic phrase prefetch is unavailable for this session.");
    }
    const cue = session.guidancePlan.cues.find((candidate) =>
      candidate.phrases.some((phrase) => phrase.id === phraseId)
    );
    const phrase = cue?.phrases.find((candidate) => candidate.id === phraseId);
    const persona = findCoachPersona(session.coachPersonaId);
    const provider = pinnedProvider(
      session.route.providerKey,
      session.route.providerEndpointKey,
      session.route.providerModel
    );
    if (!cue || !phrase || !persona || !provider) {
      throw new AIProviderError("not_eligible", "The planned coaching phrase is unavailable.");
    }
    const config = loadLiveCoachFeatureConfig();
    const result = await provider.generateCue({
      requestId: `prefetch-${phraseId}`,
      locale: session.locale,
      coachPersonaId: persona.id as CoachPersonaId,
      coachPersonaInstructions: persona.instructions,
      voiceProfileId: session.voiceProfileId as VoiceProfileId,
      providerVoice: session.route.providerVoice,
      semanticMoment: cue.moment,
      stableInstructions: stableLiveCoachInstructions(session.locale, session.compiledContext.measurementUnitSystem),
      compiledContext: session.compiledContext,
      liveState: { elapsedSeconds: 0, distanceMeters: 0, routeGuidanceActive: false },
      recentCueSummaries: [],
      maximumSpokenWordsEquivalent: 36,
      exactTranscript: phrase.text,
      deadline: new Date(Date.now() + Math.max(8_000, config.providerDeadlineMilliseconds)),
    }, signal);
    return { audio: result.audio, transcript: result.transcript };
  }

  async recordCachedUse(
    userId: string,
    sessionId: string,
    input: RequestLiveCoachCueInput
  ): Promise<void> {
    const session = await this.sessions.ownedActiveSession(userId, sessionId);
    if (session.effectiveMode !== "dynamic" || !input.selectedPhraseId) {
      throw new AIProviderError("not_eligible", "Planned cached audio is unavailable for this cue.");
    }
    const transcript = phraseForPlan(
      session.guidancePlan,
      input.selectedPhraseId,
      input.moment,
      input.liveState.workoutSegmentPhase
    );
    if (!transcript) throw new AIProviderError("not_eligible", "The planned cached phrase is invalid.");
    const created = await this.prisma.$transaction(async (tx) => {
      const current = await tx.liveCoachSession.findUniqueOrThrow({ where: { id: sessionId } });
      const existing = await tx.liveCoachCue.findUnique({
        where: { sessionId_cueRequestId: { sessionId, cueRequestId: input.cueRequestId } },
      });
      if (existing) return false;
      await tx.liveCoachCue.create({ data: {
        sessionId,
        cueRequestId: input.cueRequestId,
        moment: input.moment,
        source: "planned_cache",
        resultCategory: "success",
        contextHash: session.contextHash,
        latencyBucket: "local_cache",
        outputAudioBucket: "device_cache",
        expiresAt: new Date(Date.now() + input.validForMilliseconds),
      } });
      // This legacy field is now a per-session success marker, not a cue counter.
      await tx.liveCoachSession.update({ where: { id: sessionId }, data: { dynamicCueCount: 1 } });
      return current.dynamicCueCount === 0;
    });
    if (created && session.accessReason === "open_beta") {
      await new DatabaseLiveCoachEntitlementResolver(this.prisma).finalizeTrialRun(userId);
    }
  }
}

function pinnedProvider(providerKey: string, endpointKey: string, model: string): LiveCoachAIProvider | null {
  return buildAIProviderRegistry(loadAIProviderConfiguration()).find((provider) =>
    provider.key === providerKey && provider.endpointKey === endpointKey && provider.model === model
  ) ?? null;
}
