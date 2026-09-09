import type { CompiledContext, CompanionActionProposal } from "./types.js";

export function generateCandidateAction(prompt: string, context: CompiledContext): CompanionActionProposal {
  const normalized = prompt.toLowerCase();
  const currentState = context.currentState as { nextWorkouts?: Array<{ id: string; durationSeconds: number; title: string; scheduledDate: string; isKeyWorkout: boolean; modality: string; stimulus: string; targetCalories?: number | null }> };
  const nextWorkout = currentState.nextWorkouts?.[0];
  const signalTypes = new Set(context.situationalSignals.map((signal) => String(signal.type)));
  const asksForShorter = /short(er|en)|less time|busy|only \d+ (minute|min)/.test(normalized);
  const fatigue = /tired|fatigue|exhausted/.test(normalized) || signalTypes.has("recovery.fatigue");
  const soreness = /sore|pain|hurt/.test(normalized) || signalTypes.has("recovery.soreness");
  const unsafeWeather = ["weather.heat_risk", "weather.lightning", "weather.air_quality_risk"].some((type) => signalTypes.has(type));
  const requestedCalories = parseRequestedCalories(normalized);
  const asksForCaloriePreference = /(make|set|use|prefer).*(easy|recovery|regular).*(calorie|kcal)|calorie[- ]based.*(easy|recovery|run)/.test(normalized);
  const asksForPlanRecalibration = /\b(recalibrat(?:e|ion)|replan|reassess)\b.*\b(plan|training|workouts?)\b|\b(review|adjust|update)\b.*\b(my|the)\b.*\b(training )?plan\b/.test(normalized);

  if (asksForPlanRecalibration) {
    return {
      actionType: "recalibrate_plan",
      permissionTier: 1,
      requiresConfirmation: false,
      evidenceIds: context.includedRefs.map((reference) => reference.id),
      rationale: "The runner explicitly requested an AI review of the current training plan.",
    };
  }

  if (asksForCaloriePreference) {
    return {
      actionType: "update_run_goal_preference",
      permissionTier: 2,
      requiresConfirmation: true,
      goalType: "calories",
      evidenceIds: context.includedRefs.map((reference) => reference.id),
      rationale: "This changes eligible future easy and recovery runs, so it requires confirmation before rebuilding the plan.",
    };
  }

  if (nextWorkout && requestedCalories != null) {
    const eligible = nextWorkout.modality === "run" && ["easyAerobic", "recovery"].includes(nextWorkout.stimulus);
    if (eligible) {
      return {
        actionType: "set_workout_calories",
        permissionTier: 2,
        requiresConfirmation: true,
        workoutId: nextWorkout.id,
        targetCalories: requestedCalories,
        evidenceIds: context.includedRefs.map((reference) => reference.id),
        rationale: "The exact calorie target can replace this easy run's timed phases after weight and pace inputs are validated.",
      };
    }
  }

  if (nextWorkout && (asksForShorter || fatigue || soreness || unsafeWeather)) {
    const currentMinutes = Math.max(1, Math.round(nextWorkout.durationSeconds / 60));
    const requestedMinutes = parseRequestedMinutes(normalized);
    const durationMinutes = Math.max(15, Math.min(currentMinutes, requestedMinutes ?? Math.round(currentMinutes * (soreness ? 0.6 : 0.75) / 5) * 5));
    const reason = soreness
      ? "Soreness or pain-related context requires a conservative option and explicit confirmation."
      : unsafeWeather
        ? "Current environmental conditions make a shorter or rescheduled option safer."
        : fatigue
          ? "Current fatigue makes a reduced session a better fit than stacking the planned load."
          : "The runner's available time is shorter than the planned session.";
    return {
      actionType: "shorten_workout",
      permissionTier: 2,
      requiresConfirmation: true,
      workoutId: nextWorkout.id,
      durationMinutes,
      evidenceIds: context.includedRefs.map((reference) => reference.id),
      rationale: reason,
    };
  }

  return {
    actionType: "communicate",
    permissionTier: 0,
    requiresConfirmation: false,
    evidenceIds: context.includedRefs.map((reference) => reference.id),
    rationale: "No validated plan mutation is needed for this turn.",
  };
}

function parseRequestedMinutes(prompt: string) {
  const match = prompt.match(/(?:only\s+)?(\d{1,3})\s*(?:minute|min)/);
  return match ? Number(match[1]) : null;
}

function parseRequestedCalories(prompt: string) {
  const match = prompt.match(/(\d{2,5})\s*(?:calories|calorie|kcal|cals?)\b/);
  if (!match) return null;
  const value = Number(match[1]);
  return value >= 50 && value <= 5_000 ? value : null;
}
