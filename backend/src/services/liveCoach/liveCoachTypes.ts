import type { LiveCoachCompiledContext, LiveCoachLiveState, ResolvedAIRoute, SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachMode } from "./liveCoachFeatureConfig.js";

export const LIVE_COACH_MOMENTS = [
  "progress",
  "early_overpace",
  "pace_above_target",
  "pace_below_target",
  "pace_instability",
  "target_locked",
  "pace_drift",
  "rhythm_recovery",
  "recovery_too_hard",
  "unexpected_stop",
  "resume_after_break",
  "climb_start",
  "crest_recovery",
  "segment_transition",
  "finish_opportunity",
  "challenge_start",
  "challenge_complete",
] as const;
export type LiveCoachMoment = (typeof LIVE_COACH_MOMENTS)[number];
export type CoachingContract = "quiet" | "responsive" | "coach_me";
export type LiveCoachCueSource = "dynamic_generation" | "fixed_pack" | "cached_fallback";
export type LiveCoachCueResult =
  | "success"
  | "offline"
  | "timeout"
  | "stale"
  | "invalid"
  | "unavailable"
  | "feature_disabled"
  | "entitlement_required"
  | "quota_exhausted"
  | "budget_exhausted";

export type CreateLiveCoachSessionInput = {
  contractVersion: 1;
  clientSessionId: string;
  workoutId?: string;
  locale: SupportedAILocale;
  coachPersonaId: string;
  voiceProfileId: string;
  coachingContract: CoachingContract;
  measurementUnitSystem: "metric" | "imperial";
  sessionIntent: { activityType: "running" | "walking" | "cycling" | "hiking" | "swimming"; goalType: "workout" | "distance" | "time" | "freestyle" };
  appDistributionHint?: "global";
};

export type RequestLiveCoachCueInput = {
  contractVersion: 1;
  cueRequestId: string;
  moment: LiveCoachMoment;
  detectedAtElapsedSeconds: number;
  validForMilliseconds: number;
  liveState: LiveCoachLiveState;
};

export type EndLiveCoachSessionInput = {
  contractVersion: 1;
  spokenCueCount: number;
  helpfulCueCount: number;
  outcome: "completed" | "discarded" | "interrupted";
};

export type LiveCoachAccessReason =
  | "open_beta"
  | "verified_subscription"
  | "promotion"
  | "entitlement_required"
  | "quota_exhausted"
  | "feature_disabled";

export type LiveCoachAccessDecision = {
  capability: "live_coach_dynamic";
  allowed: boolean;
  reason: LiveCoachAccessReason;
  paywallAvailable: boolean;
};

export type CompiledLiveCoachSessionContext = {
  context: LiveCoachCompiledContext;
  serialized: string;
  contextHash: string;
  estimatedTokens: number;
};

export type LiveCoachSessionSnapshot = {
  id: string;
  userId: string;
  locale: SupportedAILocale;
  coachPersonaId: string;
  personaVersion: number;
  voiceProfileId: string;
  coachingContract: CoachingContract;
  accessReason: LiveCoachAccessReason;
  effectiveMode: LiveCoachMode;
  compiledContext: LiveCoachCompiledContext;
  contextHash: string;
  dynamicCueLimit: number;
  dynamicCueCount: number;
  expiresAt: Date;
  route: ResolvedAIRoute | null;
};

export type LiveCoachCueEnvelope = {
  contractVersion: 1;
  cueRequestId: string;
  source: LiveCoachCueSource;
  result: LiveCoachCueResult;
  moment: LiveCoachMoment;
  urgency: "steady" | "opportunity" | "caution";
  transcript: string;
  fixedCueKey?: string;
  audio?: {
    contentType: "audio/wav";
    base64: string;
    durationMilliseconds: number;
  };
  generatedAt: string;
  expiresAt: string;
};
