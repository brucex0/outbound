export const SUPPORTED_AI_LOCALES = ["en", "es", "zh-Hans"] as const;
export type SupportedAILocale = (typeof SUPPORTED_AI_LOCALES)[number];

export type AIProviderKey = "alibaba" | "google_cloud_tts" | "gemini";
export type AIMarket = "global" | "mainland_china";
export type AIRequestKind =
  | "live_coach_dynamic"
  | "live_coach_fixed_asset"
  | "assistant_text"
  | "companion_text";

export type AudioEncoding = {
  container: "wav";
  codec: "pcm_s16le";
  sampleRateHz: 24_000;
  channels: 1;
};

export const LIVE_COACH_AUDIO_ENCODING: AudioEncoding = {
  container: "wav",
  codec: "pcm_s16le",
  sampleRateHz: 24_000,
  channels: 1,
};

export const LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS = 8_000;
export const LIVE_COACH_DYNAMIC_AUDIO_MAX_DURATION_MILLISECONDS = 8_000;

export const VOICE_PROFILE_IDS = [
  "plainstride_warm_1",
  "plainstride_clear_1",
] as const;
export type VoiceProfileId = (typeof VOICE_PROFILE_IDS)[number];
export type CoachPersonaId =
  | "plainstride_supportive_v1"
  | "plainstride_focused_v1"
  | "plainstride_calm_v1";

export type ProviderCapabilities = {
  text: boolean;
  audioOutput: boolean;
  combinedTextAndAudio: boolean;
  supportedLocales: SupportedAILocale[];
  supportedMarkets: AIMarket[];
  supportedAudio: AudioEncoding[];
  maximumOutputSeconds: number;
};

export type LiveCoachLiveState = {
  elapsedSeconds: number;
  distanceMeters: number;
  currentPaceSecondsPerKilometer?: number;
  rollingPaceSecondsPerKilometer?: number;
  targetPaceSecondsPerKilometer?: number;
  gradePercent?: number;
  workoutSegmentIndex?: number;
  workoutSegmentPhase?: "warmup" | "easy" | "work" | "recovery" | "walk" | "cooldown" | "open";
  routeGuidanceActive: boolean;
};

export type LiveCoachCompiledContext = {
  version: 2;
  measurementUnitSystem: "metric" | "imperial";
  runnerModelVersion: string;
  locale: SupportedAILocale;
  activityType: "running" | "walking" | "cycling" | "hiking" | "swimming";
  goalType: "workout" | "distance" | "time" | "freestyle";
  bio: {
    biography: string | null;
    ageYears: number | null;
    sexAtBirth: string | null;
    heightCentimeters: number | null;
    weightKilograms: number | null;
    goalSummary: string | null;
    scheduleSummary: string | null;
    comfortableDurationMinutes: number | null;
    recentSessionsPerWeek: number | null;
    targetSessionsPerWeek: number | null;
    preferredLongRunDay: string | null;
    guidanceDetail: string | null;
    constraints: unknown;
  };
  coachingProfile: {
    fitnessLevel: string | null;
    weeklyVolumeKilometers: number | null;
    preferredPaceSecondsPerKilometer: number | null;
    strengths: string[];
    weaknesses: string[];
    goals: unknown;
    records: unknown;
    recentMemorySummary: unknown;
  };
  workout: {
    title: string;
    purpose: string;
    durationSeconds: number;
    intensityTarget: unknown;
    prescription: unknown;
    blocks: unknown[];
  } | null;
  clientWorkout: {
    title: string;
    detail: string;
    guideLine: string;
    targetDistanceMeters: number | null;
    targetDurationSeconds: number | null;
    steps: unknown[];
    route: unknown | null;
  } | null;
  readiness: {
    choice: string;
    energy: number | null;
    soreness: number | null;
    sleepQuality: number | null;
    stress: number | null;
    motivation: number | null;
    illnessOrPain: boolean;
    notes: string | null;
  } | null;
  surveySummary: string[];
  runnerInsights: string[];
  runnerBeliefs: string[];
  recentTraining: {
    sevenDayActivities: unknown[];
    sevenDaySummary: unknown;
    twentyEightDaySummary: unknown;
    recentWorkoutFeedback: unknown[];
  };
  environment: {
    timeZoneIdentifier: string | null;
    indoor: boolean;
    approximateLocation: unknown | null;
    weather: unknown | null;
  };
  guidancePriorities: string[];
  cuePreferences: string[];
  safetyRequiresFixedOnly: boolean;
};

export type LiveCoachGenerationInput = {
  requestId: string;
  locale: SupportedAILocale;
  coachPersonaId: CoachPersonaId;
  coachPersonaInstructions: string;
  voiceProfileId: VoiceProfileId;
  providerVoice: string;
  semanticMoment: string;
  stableInstructions: string;
  compiledContext: LiveCoachCompiledContext;
  liveState: LiveCoachLiveState;
  recentCueSummaries: string[];
  maximumSpokenWordsEquivalent: number;
  exactTranscript?: string;
  deadline: Date;
};

export type LiveCoachProviderResult = {
  transcript: string;
  audio: Uint8Array;
  audioEncoding: AudioEncoding;
  durationMilliseconds: number;
  usage: {
    inputTokens?: number;
    outputTextTokens?: number;
    outputAudioTokens?: number;
  };
  providerRequestId?: string;
};

export type LiveCoachProviderAudioStream = {
  transcript: string;
  audioEncoding: {
    container: "raw";
    codec: "pcm_s16le";
    sampleRateHz: 24_000;
    channels: 1;
  };
  chunks: AsyncIterable<Uint8Array>;
};

export interface LiveCoachAIProvider {
  readonly key: AIProviderKey;
  readonly endpointKey: string;
  readonly model: string;
  capabilities(): ProviderCapabilities;
  resolveVoice(voiceProfileId: VoiceProfileId, locale: SupportedAILocale): string | null;
  generateCue(input: LiveCoachGenerationInput, signal: AbortSignal): Promise<LiveCoachProviderResult>;
  streamCue?(input: LiveCoachGenerationInput, signal: AbortSignal): Promise<LiveCoachProviderAudioStream>;
}

export type AIRouteFacts = {
  requestKind: AIRequestKind;
  market: AIMarket;
  locale: SupportedAILocale;
  voiceProfileId: VoiceProfileId;
  requiredCapabilities: Array<"audio_output" | "combined_text_audio">;
  deploymentRegion: string;
  latencyClass: "interactive" | "offline";
  experimentKey?: string;
};

export type ResolvedAIRoute = {
  providerKey: AIProviderKey;
  providerEndpointKey: string;
  providerModel: string;
  providerVoice: string;
  routePolicyVersion: string;
};
