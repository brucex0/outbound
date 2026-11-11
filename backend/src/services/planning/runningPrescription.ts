import type { PlannedWorkoutDraft, TrainingStimulus, WorkoutBlockDraft, WorkoutGenerationInput, WorkoutStepDraft } from "./types.js";

export const RUN_STRUCTURE_VERSION = "structured-running-v1";
export type RunningWorkoutKind = "easy" | "recovery" | "long" | "run_walk" | "threshold_continuous" | "threshold_cruise" | "aerobic_intervals";

export function runningPhaseIntensity(kind: string): "threshold" | "speed" | "unknown" | null {
  return ["threshold", "tempo"].includes(kind) ? "threshold" : ["speed", "interval", "hill"].includes(kind) ? "speed"
    : ["work", "race", "racePrep", "fartlek"].includes(kind) ? "unknown" : null;
}

/** Explicit authored short relaxed repetitions, not aerobic interval/VO2 work. */
export function isShortSourceRepetition(workout: PlannedWorkoutDraft): boolean {
  if (workout.prescription.sourceWorkoutKind !== "racePrep") return false;
  const phases = workout.blocks.flatMap((block) => block.steps);
  const work = phases.map((phase, index) => ({ phase, index })).filter(({ phase }) => runningPhaseIntensity(phase.kind));
  return work.length >= 3 && work.length <= 6 && work.every(({ phase }) => (phase.durationSeconds ?? 0) >= 15 && (phase.durationSeconds ?? 0) <= 45)
    && work.slice(0, -1).every((item, index) => phases.slice(item.index + 1, work[index + 1].index)
      .filter((phase) => phase.kind === "recovery").reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0) >= 60);
}

/** A bounded accepted source recipe retains work/recovery semantics and exact total. */
export function limitRunningQuality(workout: PlannedWorkoutDraft, allowanceSeconds: number): PlannedWorkoutDraft | null {
  const phases = workout.blocks.flatMap((block) => block.steps);
  const original = phases.filter((phase) => runningPhaseIntensity(phase.kind)).reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0);
  const limit = Math.max(0, Math.floor(allowanceSeconds));
  const hasThreshold = phases.some((phase) => runningPhaseIntensity(phase.kind) === "threshold");
  const shortRepetitions = isShortSourceRepetition(workout);
  const meaningful = shortRepetitions ? phases.filter((phase) => runningPhaseIntensity(phase.kind)).slice(0, 3)
    .reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0) : hasThreshold ? 360 : 240;
  const mark = (value: PlannedWorkoutDraft, accepted: number) => ({ ...value, prescription: { ...value.prescription,
    ...(shortRepetitions ? { sourceQualityVariant: "short_relaxed_repetitions" } : {}),
    sourceQualityRecipe: { policyVersion: "source-quality-recipe-v1", authoredQualitySeconds: original, acceptedQualitySeconds: accepted } } });
  if (original < meaningful) return null;
  if (original <= limit) return shortRepetitions ? mark(workout, original) : workout;
  if (limit < Math.min(meaningful, original)) return null;
  let remaining = limit, accepted = 0;
  const blocks = workout.blocks.map((block) => ({ ...block, steps: block.steps.flatMap((phase) => {
    const intensity = runningPhaseIntensity(phase.kind);
    if (!intensity) return [phase];
    const seconds = phase.durationSeconds ?? 0;
    const minimumBout = shortRepetitions ? seconds : intensity === "threshold" ? 180 : 60;
    const work = remaining >= Math.min(minimumBout, seconds) ? Math.min(seconds, remaining) : 0;
    remaining -= work; accepted += work;
    const easy = seconds - work;
    return [...(work ? [{ ...phase, durationSeconds: work }] : []), ...(easy ? [step("Easy run", "run", easy, [2, 4], "You should be able to speak in short sentences.")] : [])];
  }) }));
  if (accepted < Math.min(meaningful, original)) return null;
  const { summary, purpose, guideCue, effortLabel } = workout.prescription;
  return synchronizeRunningPrescription(mark({ ...workout, blocks, prescription: { ...workout.prescription,
    summary: undefined, purpose: undefined, guideCue: undefined, effortLabel: undefined,
    authoredContext: workout.prescription.authoredContext ?? { summary, purpose, guideCue, effortLabel },
    sourceQualityRecipe: { policyVersion: "source-quality-recipe-v1", authoredQualitySeconds: original, acceptedQualitySeconds: accepted } } }, accepted));
}

/** Original product heuristics: bounded doses, effort-based until benchmark evidence exists. */
export function buildRunningWorkout(input: WorkoutGenerationInput, qualityLimitSeconds?: number): PlannedWorkoutDraft {
  const total = Math.max(input.allowShortSession ? 600 : 1500, Math.round(input.durationMinutes * 60));
  const run = input.athleteState.modalityBreakdown.run as { minutes?: number; sessions?: number; activeWeeks?: number } | undefined;
  const weeklyMinutes = Math.max(0, (run?.minutes ?? 0) / 4);
  const runWalk = input.runWalk === true || input.baselineContext != null && input.baselineContext !== "currentlyActive";
  const eligible = !runWalk && input.athleteState.fatigueRisk === "low" && input.athleteState.adherenceRate >= 0.75
    && (run?.sessions ?? 0) >= 6 && (run?.activeWeeks ?? 0) >= 3;
  let stimulus: TrainingStimulus = eligible || !["threshold", "speed"].includes(input.stimulus) ? input.stimulus : "easyAerobic";
  // Original short-session policy: 40% preparation, capped at the normal 10min.
  // Deriving the combined budget first keeps main time monotonic at every second.
  const preparation = Math.min(600, Math.floor(total * 0.4));
  const warmup = Math.floor(preparation / 2);
  const cooldown = preparation - warmup;
  const mainBudget = total - warmup - cooldown;
  const requestedHard = stimulus === "threshold" || stimulus === "speed";
  const hardLimit = Math.min(qualityLimitSeconds ?? Infinity,
    stimulus === "speed" ? 720 : 1200,
    Math.floor(weeklyMinutes * 60 * (stimulus === "speed" ? 0.08 : 0.10)),
    Math.floor(mainBudget * (stimulus === "speed" ? 0.5 : 0.65)));
  if (requestedHard && hardLimit < (stimulus === "speed" ? 240 : 360)) stimulus = "easyAerobic";
  let kind: RunningWorkoutKind = runWalk ? "run_walk" : stimulus === "longEndurance" ? "long" : stimulus === "recovery" ? "recovery" : "easy";
  const main: WorkoutStepDraft[] = [];
  if (runWalk && input.runWalkStage?.continuousTrial) {
    main.push(step("Comfortable run-walk", "run", mainBudget, [2, 4], "Alternate comfortable jogging and walking as needed; keep the whole main session easy."));
  } else if (runWalk) {
    let remaining = mainBudget;
    while (remaining > 0) {
      const runSeconds = Math.min(input.runWalkStage?.runSeconds ?? 60, remaining);
      main.push(step("Comfortable run-walk", "run", runSeconds, [2, 4], "Alternate comfortable jogging and walking as needed; keep the whole main session easy."));
      remaining -= runSeconds;
      if (remaining > 0) {
        const walkSeconds = Math.min(input.runWalkStage?.walkSeconds ?? 90, remaining);
        main.push(step("Walk recovery", "walk", walkSeconds, [1, 2], "Walk until your breathing settles."));
        remaining -= walkSeconds;
      }
    }
  } else if (stimulus === "threshold") {
    const quality = Math.floor(hardLimit / 60) * 60;
    if (quality >= 900) {
      kind = "threshold_continuous";
      main.push(step("Tempo effort", "threshold", quality, [6, 7], "Strong but controlled; never sprinting."));
    } else {
      kind = "threshold_cruise";
      const bouts = Math.min(4, Math.floor(quality / 180));
      for (let index = 0; index < bouts; index++) {
        main.push(step("Tempo effort", "threshold", 180, [6, 7], "Strong but controlled; never sprinting."));
        if (index < bouts - 1) main.push(step("Easy recovery", "recovery", 60, [2, 3], "Recover easily before the next effort."));
      }
    }
  } else if (stimulus === "speed") {
    kind = "aerobic_intervals";
    const bouts = Math.min(6, Math.floor(hardLimit / 120));
    for (let index = 0; index < bouts; index++) {
      main.push(step("Fast relaxed running", "speed", 120, [7, 8], "Fast enough to feel sharp, relaxed enough to stay smooth."));
      if (index < bouts - 1) main.push(step("Easy recovery", "recovery", 90, [2, 3], "Recover easily before the next effort."));
    }
  }
  const used = main.reduce((sum, item) => sum + (item.durationSeconds ?? 0), 0);
  if (used < mainBudget) main.push(step(stimulus === "longEndurance" ? "Long aerobic running" : stimulus === "recovery" ? "Very easy jog" : "Easy run",
    stimulus === "recovery" ? "recovery" : "run", mainBudget - used, stimulus === "recovery" ? [1, 3] : [2, 4],
    stimulus === "longEndurance" ? "Keep this patient and conversational." : "You should be able to speak in short sentences."));
  const blocks: WorkoutBlockDraft[] = [
    block("warmup", "easyAerobic", [step(runWalk ? "Warm up walk" : "Warm up jog", "warmup", warmup, [2, 3], "Start easier than you think you need to.")]),
    block("main", stimulus, main),
    block("cooldown", "recovery", [step("Cooldown walk", "cooldown", cooldown, [1, 2], "Let your breathing settle before you stop.")]),
  ];
  const title = runWalk ? "Easy run-walk" : stimulus === "threshold" ? "Controlled tempo run" : stimulus === "speed" ? "Relaxed speed session"
    : stimulus === "longEndurance" ? "Long easy run" : stimulus === "recovery" ? "Recovery jog" : "Easy aerobic run";
  const workout: PlannedWorkoutDraft = {
    scheduledDate: input.scheduledDate, modality: "run", stimulus, title, durationSeconds: total,
    distanceMeters: input.distanceMeters ?? null, targetCalories: input.targetCalories ?? null,
    intensityModel: "rpe", intensityTarget: { min: stimulus === "threshold" ? 6 : stimulus === "speed" ? 7 : 2, max: stimulus === "threshold" ? 7 : stimulus === "speed" ? 8 : 4 },
    prescription: { source: "generatedRun", runStructureVersion: RUN_STRUCTURE_VERSION, workoutKind: kind, runWalk,
      allowShortSession: input.allowShortSession === true, weeklyRunMinutes: weeklyMinutes, baselineContext: input.baselineContext ?? "currentlyActive" },
    isKeyWorkout: !runWalk && ["threshold", "speed", "longEndurance"].includes(stimulus), blocks,
  };
  return synchronizeRunningPrescription(workout);
}

/** Explicit phase rows are authoritative. No repeats multiplier is used. */
export function synchronizeRunningPrescription(workout: PlannedWorkoutDraft): PlannedWorkoutDraft {
  if (workout.modality !== "run") return workout;
  const steps = workout.blocks.flatMap((item) => item.steps);
  const secondsFor = (type: string) => steps.filter((item) => runningPhaseIntensity(item.kind) === type).reduce((sum, item) => sum + (item.durationSeconds ?? 0), 0);
  const thresholdSeconds = secondsFor("threshold");
  const speedSeconds = secondsFor("speed");
  const unknownQualitySeconds = secondsFor("unknown");
  return { ...workout, blocks: workout.blocks.map((item) => ({ ...item,
    durationSeconds: item.steps.reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0), repeats: null, restSeconds: null })),
    prescription: { ...workout.prescription, qualitySeconds: thresholdSeconds + speedSeconds + unknownQualitySeconds,
      intensitySeconds: { threshold: thresholdSeconds, speed: speedSeconds, unknown: unknownQualitySeconds },
      blocks: workout.blocks.map((item) => ({ type: item.blockType, durationSeconds: item.steps.reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0) })),
      steps: steps.map((item) => ({ ...item })) },
  };
}

/** Resize only timed phase data; preserve non-running and distance/calorie contracts at callers. */
export function resizeTimedRunningWorkout(workout: PlannedWorkoutDraft, seconds: number, soften = false, minimumMainSeconds = 0): PlannedWorkoutDraft {
  const target = Math.round(seconds);
  if (workout.modality !== "run" || target <= 0) return workout;
  const blocks = workout.blocks.map((item) => ({ ...item, steps: item.steps.map((phase) => ({ ...phase })) }));
  const phases = blocks.flatMap((item) => item.steps);
  if (soften) for (const block of blocks) if (block.blockType === "main") block.stimulus = "recovery";
  const total = phases.reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0);
  const isHard = (phase: WorkoutStepDraft) => ["threshold", "tempo", "speed", "interval", "hill", "work", "race", "racePrep", "fartlek"].includes(phase.kind);
  const mainPhases = blocks.filter((item) => item.blockType === "main").flatMap((item) => item.steps);
  const supporting = phases.filter((phase) => !mainPhases.includes(phase));
  const mainTotal = mainPhases.reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0);
  const desiredMain = mainTotal ? Math.max(Math.min(minimumMainSeconds, mainTotal), Math.round(mainTotal * target / Math.max(total, 1))) : 0;
  if (minimumMainSeconds > 0 && desiredMain >= target && supporting.length) throw new Error("The requested duration cannot retain the main-session minimum.");
  function allocate(group: WorkoutStepDraft[], budget: number) {
    const original = group.reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0);
    const fixed = budget > original ? group.filter(isHard).reduce((sum, phase) => sum + (phase.durationSeconds ?? 0), 0) : 0;
    let used = 0;
    for (const [index, phase] of group.entries()) {
      phase.durationSeconds = index === group.length - 1 ? budget - used : fixed > 0 && isHard(phase) ? (phase.durationSeconds ?? 0)
        : Math.max(1, Math.floor((phase.durationSeconds ?? 0) * (budget - fixed) / Math.max(original - fixed, 1)));
      used += phase.durationSeconds;
      if (soften && isHard(phase)) {
        phase.kind = "run"; phase.label = "Easy run"; phase.target = { rpe: [2, 4] }; phase.detail = "You should be able to speak in short sentences.";
      }
    }
  }
  if (mainPhases.length && supporting.length && minimumMainSeconds > 0) {
    allocate(mainPhases, desiredMain); allocate(supporting, target - desiredMain);
  } else allocate(phases, target);
  return synchronizeRunningPrescription({ ...workout, blocks, durationSeconds: target,
    ...(soften ? { title: workout.prescription.runWalk ? "Easy run-walk" : "Easy aerobic run", stimulus: "recovery" as const,
      isKeyWorkout: false, intensityModel: "rpe", intensityTarget: { min: 2, max: 4 } } : {}),
    prescription: { ...workout.prescription, ...(soften ? { workoutKind: workout.prescription.runWalk ? "run_walk" : "recovery", readinessAdjusted: true,
      summary: "You should be able to speak in short sentences.", purpose: "Keep the whole thing restorative.", guideCue: "You should be able to speak in short sentences.", effortLabel: "Easy" } : {}) },
  });
}
function step(label: string, kind: string, durationSeconds: number, rpe: number[], detail: string): WorkoutStepDraft {
  return { label, kind, durationSeconds, target: { rpe }, detail };
}
function block(blockType: string, stimulus: TrainingStimulus, steps: WorkoutStepDraft[]): WorkoutBlockDraft {
  return { blockType, modality: "run", stimulus, durationSeconds: steps.reduce((sum, item) => sum + (item.durationSeconds ?? 0), 0),
    metadata: { runStructureVersion: RUN_STRUCTURE_VERSION }, steps };
}
