import { buildRunningWorkout } from "../runningPrescription.js";
import type {
  CompletionEvaluationInput,
  CompletionQuality,
  ModalityAdapter,
  ModalityProgression,
  PlannedWorkoutDraft,
  ProgressionInput,
  StimulusRequest,
  TrainingStressEstimate,
  WorkoutGenerationInput,
} from "../types.js";

export const runAdapter: ModalityAdapter = {
  modality: "run",

  canSatisfy(input: StimulusRequest) {
    return input.modality === "run" && input.stimulus !== "strength" && input.stimulus !== "hypertrophy";
  },

  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft {
    return buildRunningWorkout(input);
  },

  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate {
    const multiplier = workout.stimulus === "threshold" || workout.stimulus === "speed" ? 1.45 : 1;
    return {
      score: Math.round((workout.durationSeconds / 60) * multiplier),
      hard: multiplier > 1,
    };
  },

  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality {
    if (input.workout.targetCalories && input.completion.energyKilocalories != null) {
      if (input.completion.energyKilocalories < input.workout.targetCalories * 0.6) return "partial";
    }
    const duration = input.completion.durationSeconds ?? 0;
    if (duration < input.workout.durationSeconds * 0.6) return "partial";
    if (input.completion.completionQuality === "tooHard") return "tooHard";
    if (input.completion.completionQuality === "feltEasy") return "feltEasy";
    return "completed";
  },

  progress(input: ProgressionInput): ModalityProgression {
    const baseline = Math.max(20, Math.round(input.athleteState.fourWeekAvgMinutes / 3));
    return { durationMinutes: baseline };
  },
};
