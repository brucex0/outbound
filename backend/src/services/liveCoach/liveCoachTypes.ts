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
export type LiveCoachCueSource = "dynamic_generation" | "planned_cache" | "fixed_pack" | "cached_fallback";
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
  clientWorkout?: LiveCoachClientWorkout;
  environment?: LiveCoachEnvironmentInput;
  appDistributionHint?: "global";
};

export type LiveCoachClientWorkout = {
  title: string;
  detail: string;
  guideLine: string;
  targetDistanceMeters?: number;
  targetDurationSeconds?: number;
  steps: Array<{
    label: string;
    durationSeconds: number;
    detail?: string;
    phase?: "warmup" | "easy" | "work" | "recovery" | "walk" | "cooldown" | "open";
    targetPaceSecondsPerKilometer?: number;
  }>;
  route?: {
    name?: string;
    shape?: string;
    direction?: "forward" | "reverse";
    distanceMeters?: number;
    elevationGainMeters?: number;
    approximateStartLatitude?: number;
    approximateStartLongitude?: number;
    approximateStartAltitudeMeters?: number;
  };
};

export type LiveCoachEnvironmentInput = {
  timeZoneIdentifier?: string;
  indoor: boolean;
  approximateLocation?: {
    placeName?: string;
    latitude?: number;
    longitude?: number;
    altitudeMeters?: number;
  };
  weather?: {
    observedAt: string;
    condition: string;
    temperatureCelsius: number;
    apparentTemperatureCelsius: number;
    windKilometersPerHour: number;
    precipitationChance: number;
    impact: "none" | "advisory" | "caution" | "unsafe";
    headline: string;
    guidance?: string;
    bestWindow?: string;
  };
};

export type LiveCoachGuidancePhase = "any" | "warmup" | "easy" | "work" | "recovery" | "walk" | "cooldown" | "open";
export type LiveCoachGuidancePlanCue = {
  id: string;
  moment: LiveCoachMoment;
  phases: LiveCoachGuidancePhase[];
  priority: "steady" | "opportunity" | "caution";
  cooldownSeconds: number;
  phrases: Array<{ id: string; text: string }>;
};
export type LiveCoachGuidancePlan = {
  contractVersion: 1;
  planVersion: string;
  locale: SupportedAILocale;
  summary: string;
  progressPolicy: {
    announceEverySeconds: number;
    announceEveryMeters: number;
    includePace: boolean;
  };
  cues: LiveCoachGuidancePlanCue[];
};

export type RequestLiveCoachCueInput = {
  contractVersion: 1;
  cueRequestId: string;
  moment: LiveCoachMoment;
  detectedAtElapsedSeconds: number;
  validForMilliseconds: number;
  selectedPhraseId?: string;
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
  guidancePlan: LiveCoachGuidancePlan;
  guidancePlanHash: string;
  plannerStatus: "generated" | "fallback";
  plannerModel: string | null;
  plannerPromptVersion: string;
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
