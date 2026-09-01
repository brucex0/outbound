import rawStandaloneWorkoutCatalog from "./standaloneWorkouts.json" with { type: "json" };

export type StandaloneCoachingTarget = {
  phase: "warmup" | "easy" | "work" | "recovery" | "walk" | "cooldown" | "open";
  pace?: {
    reference: "athlete_reference" | "absolute";
    targetSecondsPerKilometer?: number;
    athleteReferenceOffsetSeconds: number;
    fasterToleranceSeconds: number;
    slowerToleranceSeconds?: number;
  };
  recognizesTargetLock: boolean;
};

export type StandaloneGuideTrigger =
  | { type: "distance"; startMeters: number; endMeters: number }
  | { type: "elapsed_time"; startSeconds: number; endSeconds: number };

export type StandaloneGuideInstruction = {
  id: string;
  trigger: StandaloneGuideTrigger;
  effort: {
    rpeMin: number;
    rpeMax: number;
    feel: string;
  };
  instruction: string;
  cue: string;
  fallback: string;
};

export type StandaloneWorkoutCatalogItem = {
  id: string;
  title: string;
  subtitle: string;
  durationLabel: string;
  systemImage: string;
  sport: "run" | "bike";
  category: "guided_distance" | "easy" | "recovery" | "speed" | "tempo" | "fartlek" | "hill" | "walk_run";
  detail: string;
  guideLine: string;
  startLabel: string;
  targetDistanceMeters?: number;
  targetDurationSeconds?: number;
  steps: Array<{
    id: string;
    label: string;
    durationSeconds: number;
    detail?: string;
    coachingTarget?: StandaloneCoachingTarget;
  }>;
  coachingTarget?: StandaloneCoachingTarget;
  prerequisites: string[];
  guideInstructions: {
    objective: string;
    beforeStart: string[];
    segments: StandaloneGuideInstruction[];
    finish: string[];
    stopConditions: string[];
  };
  sourceRefs: string[];
};

export type StandaloneWorkoutCatalog = {
  version: number;
  locale: "en";
  measurementSystem: "metric";
  editorialPolicy: {
    authorship: string;
    medicalScope: string;
    longDistanceScope: string;
  };
  effortScale: {
    type: "rpe_1_10";
    anchors: Array<{ value: number; label: string; description: string }>;
  };
  sources: Array<{
    id: string;
    publisher: string;
    title: string;
    url: string;
    usage: string;
  }>;
  workouts: StandaloneWorkoutCatalogItem[];
};

export const standaloneWorkoutCatalog = rawStandaloneWorkoutCatalog as StandaloneWorkoutCatalog;
