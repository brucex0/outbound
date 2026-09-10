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
    transitionInstruction?: string;
    transitionLeadSeconds?: number;
    transitionCountdown?: "none" | "five_second";
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

const rawCatalog = rawStandaloneWorkoutCatalog as StandaloneWorkoutCatalog;

function transitionInstruction(step: StandaloneWorkoutCatalogItem["steps"][number]): string {
  const detail = step.detail?.replace(/[.!?]+$/, "");
  const action = detail ? `${step.label}: ${detail}.` : `${step.label}.`;
  switch (step.coachingTarget?.phase) {
    case "recovery": return `Ease into recovery. ${action}`;
    case "walk": return `Shift into the walk and let your effort settle. ${action}`;
    case "cooldown": return `Bring the effort down smoothly. ${action}`;
    case "warmup": return `Start relaxed and build gradually. ${action}`;
    case "work": return `Make the transition with control. ${action}`;
    default: return `Flow into the next effort. ${action}`;
  }
}

export const standaloneWorkoutCatalog: StandaloneWorkoutCatalog = {
  ...rawCatalog,
  workouts: rawCatalog.workouts.map((workout) => ({
    ...workout,
    steps: workout.steps.map((step, index) => ({
      ...step,
      transitionInstruction: step.transitionInstruction ?? transitionInstruction(step),
      transitionLeadSeconds: step.transitionLeadSeconds ?? 5,
      transitionCountdown: step.transitionCountdown
        ?? (index > 0 && ["recovery", "walk"].includes(step.coachingTarget?.phase ?? "")
          ? "five_second"
          : "none"),
    })),
  })),
};
