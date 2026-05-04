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
    const duration = Math.max(12, Math.round(input.durationMinutes));
    const easyMinutes = Math.max(6, duration - 10);
    const title = titleForStimulus(input.stimulus);
    const isHard = input.stimulus === "threshold" || input.stimulus === "speed";

    return {
      scheduledDate: input.scheduledDate,
      modality: "run",
      stimulus: input.stimulus,
      title,
      durationSeconds: duration * 60,
      distanceMeters: null,
      intensityModel: "rpe",
      intensityTarget: { min: isHard ? 6 : 3, max: isHard ? 8 : 5 },
      prescription: {
        blocks: [
          { type: "warmup", durationSeconds: 5 * 60 },
          { type: input.stimulus, durationSeconds: easyMinutes * 60 },
          { type: "cooldown", durationSeconds: 5 * 60 },
        ],
      },
      isKeyWorkout: input.isKeyWorkout ?? (input.stimulus === "longEndurance" || isHard),
      blocks: [
        {
          blockType: "warmup",
          modality: "run",
          stimulus: "easyAerobic",
          durationSeconds: 5 * 60,
          metadata: {},
          steps: [
            {
              label: "Warm up jog",
              kind: "warmup",
              durationSeconds: 5 * 60,
              target: { rpe: 3 },
              detail: "Start easier than you think you need to.",
            },
          ],
        },
        {
          blockType: "main",
          modality: "run",
          stimulus: input.stimulus,
          durationSeconds: easyMinutes * 60,
          metadata: { title },
          steps: [
            {
              label: mainLabelForStimulus(input.stimulus),
              kind: input.stimulus,
              durationSeconds: easyMinutes * 60,
              target: { rpe: isHard ? 7 : 4 },
              detail: detailForStimulus(input.stimulus),
            },
          ],
        },
        {
          blockType: "cooldown",
          modality: "run",
          stimulus: "recovery",
          durationSeconds: 5 * 60,
          metadata: {},
          steps: [
            {
              label: "Cooldown walk",
              kind: "cooldown",
              durationSeconds: 5 * 60,
              target: { rpe: 2 },
              detail: "Let your breathing settle before you stop.",
            },
          ],
        },
      ],
    };
  },

  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate {
    const multiplier = workout.stimulus === "threshold" || workout.stimulus === "speed" ? 1.45 : 1;
    return {
      score: Math.round((workout.durationSeconds / 60) * multiplier),
      hard: multiplier > 1,
    };
  },

  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality {
    const duration = input.completion.durationSeconds ?? 0;
    if (duration < input.workout.durationSeconds * 0.6) return "partial";
    if ((input.completion.perceivedEffort ?? 0) >= 9) return "tooHard";
    if ((input.completion.perceivedEffort ?? 5) <= 2) return "feltEasy";
    return "completed";
  },

  progress(input: ProgressionInput): ModalityProgression {
    const baseline = Math.max(20, Math.round(input.athleteState.fourWeekAvgMinutes / 3));
    return { durationMinutes: baseline };
  },
};

function titleForStimulus(stimulus: string): string {
  switch (stimulus) {
    case "longEndurance":
      return "Long easy run";
    case "threshold":
      return "Controlled tempo run";
    case "speed":
      return "Relaxed speed session";
    case "recovery":
      return "Recovery jog";
    default:
      return "Easy aerobic run";
  }
}

function mainLabelForStimulus(stimulus: string): string {
  switch (stimulus) {
    case "longEndurance":
      return "Long aerobic running";
    case "threshold":
      return "Tempo effort";
    case "speed":
      return "Fast relaxed running";
    case "recovery":
      return "Very easy jog";
    default:
      return "Easy run";
  }
}

function detailForStimulus(stimulus: string): string {
  switch (stimulus) {
    case "longEndurance":
      return "Keep this patient and conversational.";
    case "threshold":
      return "Strong but controlled; never sprinting.";
    case "speed":
      return "Fast enough to feel sharp, relaxed enough to stay smooth.";
    case "recovery":
      return "Keep the whole thing restorative.";
    default:
      return "You should be able to speak in short sentences.";
  }
}
