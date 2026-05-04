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

export const strengthAdapter: ModalityAdapter = {
  modality: "strength",

  canSatisfy(input: StimulusRequest) {
    return input.modality === "strength" || input.stimulus === "strength" || input.stimulus === "hypertrophy";
  },

  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft {
    const duration = Math.max(20, Math.round(input.durationMinutes));

    return {
      scheduledDate: input.scheduledDate,
      modality: "strength",
      stimulus: input.stimulus === "hypertrophy" ? "hypertrophy" : "strength",
      title: "Full-body strength",
      durationSeconds: duration * 60,
      distanceMeters: null,
      intensityModel: "rpe",
      intensityTarget: { min: 6, max: 7 },
      prescription: {
        blocks: [
          {
            type: "strength",
            exercises: [
              { name: "Squat pattern", sets: 3, reps: 8, target: { rpe: 7 } },
              { name: "Hinge pattern", sets: 3, reps: 8, target: { rpe: 7 } },
              { name: "Push or pull", sets: 3, reps: 10, target: { rpe: 7 } },
            ],
          },
        ],
      },
      isKeyWorkout: input.isKeyWorkout ?? false,
      blocks: [
        {
          blockType: "strength",
          modality: "strength",
          stimulus: input.stimulus === "hypertrophy" ? "hypertrophy" : "strength",
          durationSeconds: duration * 60,
          metadata: { sets: 3, reps: 8 },
          steps: [
            {
              label: "Full-body strength circuit",
              kind: "strength",
              durationSeconds: duration * 60,
              target: { rpe: 7 },
              detail: "Keep two or three reps in reserve. Leave the session better than you started.",
            },
          ],
        },
      ],
    };
  },

  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate {
    return { score: Math.round((workout.durationSeconds / 60) * 0.9), hard: true };
  },

  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality {
    if ((input.completion.perceivedEffort ?? 0) >= 9) return "tooHard";
    return "completed";
  },

  progress(_input: ProgressionInput): ModalityProgression {
    return { durationMinutes: 30 };
  },
};
