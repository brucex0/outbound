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

export const walkAdapter: ModalityAdapter = {
  modality: "walk",

  canSatisfy(input: StimulusRequest) {
    return input.modality === "walk" && ["easyAerobic", "longEndurance", "recovery"].includes(input.stimulus);
  },

  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft {
    const duration = Math.max(10, Math.round(input.durationMinutes));
    const title = input.stimulus === "longEndurance" ? "Long brisk walk" : "Brisk walk";

    return {
      scheduledDate: input.scheduledDate,
      modality: "walk",
      stimulus: input.stimulus,
      title,
      durationSeconds: duration * 60,
      distanceMeters: null,
      intensityModel: "rpe",
      intensityTarget: { min: 2, max: input.stimulus === "recovery" ? 3 : 5 },
      prescription: { blocks: [{ type: "walk", durationSeconds: duration * 60 }] },
      isKeyWorkout: input.isKeyWorkout ?? input.stimulus === "longEndurance",
      blocks: [
        {
          blockType: "main",
          modality: "walk",
          stimulus: input.stimulus,
          durationSeconds: duration * 60,
          metadata: {},
          steps: [
            {
              label: title,
              kind: "walk",
              durationSeconds: duration * 60,
              target: { rpe: input.stimulus === "recovery" ? 2 : 4 },
              detail: "Move with purpose, but keep it sustainable.",
            },
          ],
        },
      ],
    };
  },

  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate {
    return { score: Math.round(workout.durationSeconds / 90), hard: false };
  },

  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality {
    const duration = input.completion.durationSeconds ?? 0;
    return duration >= input.workout.durationSeconds * 0.7 ? "completed" : "partial";
  },

  progress(input: ProgressionInput): ModalityProgression {
    return { durationMinutes: Math.max(20, Math.round(input.athleteState.fourWeekAvgMinutes / 3)) };
  },
};
