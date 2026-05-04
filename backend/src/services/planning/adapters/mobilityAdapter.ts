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

export const mobilityAdapter: ModalityAdapter = {
  modality: "mobility",

  canSatisfy(input: StimulusRequest) {
    return input.modality === "mobility" || input.stimulus === "mobility" || input.stimulus === "recovery";
  },

  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft {
    const duration = Math.max(8, Math.round(input.durationMinutes));

    return {
      scheduledDate: input.scheduledDate,
      modality: "mobility",
      stimulus: "mobility",
      title: "Mobility reset",
      durationSeconds: duration * 60,
      distanceMeters: null,
      intensityModel: "open",
      intensityTarget: { effort: "gentle" },
      prescription: { blocks: [{ type: "mobility", durationSeconds: duration * 60 }] },
      isKeyWorkout: false,
      blocks: [
        {
          blockType: "mobility",
          modality: "mobility",
          stimulus: "mobility",
          durationSeconds: duration * 60,
          metadata: {},
          steps: [
            {
              label: "Easy mobility flow",
              kind: "mobility",
              durationSeconds: duration * 60,
              target: { effort: "gentle" },
              detail: "Move through hips, calves, back, and shoulders without forcing range.",
            },
          ],
        },
      ],
    };
  },

  estimateStress(_workout: PlannedWorkoutDraft): TrainingStressEstimate {
    return { score: 5, hard: false };
  },

  evaluateCompletion(_input: CompletionEvaluationInput): CompletionQuality {
    return "completed";
  },

  progress(_input: ProgressionInput): ModalityProgression {
    return { durationMinutes: 12 };
  },
};
