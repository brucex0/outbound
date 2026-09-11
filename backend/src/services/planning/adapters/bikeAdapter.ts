import type {
  CompletionEvaluationInput, CompletionQuality, ModalityAdapter, ModalityProgression,
  PlannedWorkoutDraft, ProgressionInput, StimulusRequest, TrainingStressEstimate,
  WorkoutGenerationInput,
} from "../types.js";

export const bikeAdapter: ModalityAdapter = {
  modality: "bike",
  canSatisfy(input: StimulusRequest) {
    return input.modality === "bike" && ["easyAerobic", "longEndurance", "threshold", "speed", "recovery"].includes(input.stimulus);
  },
  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft {
    const duration = Math.max(20, Math.round(input.durationMinutes));
    const hard = input.stimulus === "threshold" || input.stimulus === "speed";
    const title = input.stimulus === "longEndurance" ? "Long endurance ride" : hard ? "Controlled bike intervals" : input.stimulus === "recovery" ? "Recovery spin" : "Easy aerobic ride";
    return {
      scheduledDate: input.scheduledDate, modality: "bike", stimulus: input.stimulus, title,
      durationSeconds: duration * 60, distanceMeters: null, intensityModel: "rpe",
      intensityTarget: { min: hard ? 6 : 2, max: hard ? 8 : 5 },
      prescription: { blocks: [{ type: input.stimulus, durationSeconds: duration * 60 }] },
      isKeyWorkout: input.isKeyWorkout ?? (hard || input.stimulus === "longEndurance"),
      blocks: [{
        blockType: "main", modality: "bike", stimulus: input.stimulus, durationSeconds: duration * 60,
        metadata: {}, steps: [{ label: title, kind: input.stimulus, durationSeconds: duration * 60,
          target: { rpe: hard ? 7 : 4 }, detail: hard ? "Keep every effort controlled and spin easily between repeats." : "Use a smooth cadence and sustainable pressure." }],
      }],
    };
  },
  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate {
    const hard = workout.stimulus === "threshold" || workout.stimulus === "speed";
    return { score: Math.round(workout.durationSeconds / 60 * (hard ? 1.2 : 0.75)), hard };
  },
  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality {
    return (input.completion.durationSeconds ?? 0) >= input.workout.durationSeconds * 0.7 ? "completed" : "partial";
  },
  progress(input: ProgressionInput): ModalityProgression {
    return { durationMinutes: Math.max(25, Math.round(input.athleteState.fourWeekAvgMinutes / 3)) };
  },
};
