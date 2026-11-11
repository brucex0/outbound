import { computeAthleteTrainingState } from "./athleteState.js";
import { buildRunningWorkout, isShortSourceRepetition, limitRunningQuality, resizeTimedRunningWorkout, synchronizeRunningPrescription } from "./runningPrescription.js";
import { adequateRunningEvidence, evaluateRunWalkProgramme, RUN_WALK_LADDER, stampIssuedRunningDose, type PrescribedRunningEvidence, type RunWalkProgramme } from "./runWalkProgramme.js";
import { ProgrammeTimelineError, ProgrammeConstraintError, RunningScheduleError, RUNNING_DOSE_POLICY, runningDoseBudget, assertAuthoredRunningDose, shortRunningSessionsAllowed } from "./runningDosePolicy.js";
import { toPlannedWorkout } from "./catalogTemplate.js";
import { instantiateCatalogWeek } from "./catalogTemplate.js";
import { applyRunningBenchmark, runningBenchmarkDecision } from "./runningBenchmark.js";
import { phaseForGoal, type GeneratePlanInput } from "./generator.js";
import type { PlanGenerationResult } from "./types.js";
import type { TrainingPlanTemplate } from "../trainingPlans.js";

export const CATALOG_POLICY_VERSION = "catalog-programme-v4";
export interface ProgrammeCursor {
  templateID: string;
  weekIndex: number;
  weekAnchor: string;
  episodeStart: string;
  status: "active" | "completed";
}
export interface ProgrammeEvidence {
  scheduledDate: Date;
  status: string;
  prescription: unknown;
  durationSeconds: number;
  completions: { durationSeconds: number | null; completionQuality: string; perceivedEffort: number | null }[];
}
export type ProgrammeOutcome = "initial" | "same_week" | "advanced" | "repeated" | "completed";

/** Product heuristic, not a validated physiological readiness threshold. */
export function generateCatalogWindow(input: {
  template: TrainingPlanTemplate;
  goal: GeneratePlanInput["goal"];
  now: Date;
  createdAt: Date;
  priorDecision?: Record<string, unknown>;
  evidence: ProgrammeEvidence[];
  readyToAdvance: boolean;
  explicitDifficulty: boolean;
  athleteState?: import("./types.js").AthleteTrainingStateSnapshot;
  runWalkProgramme?: RunWalkProgramme;
}): PlanGenerationResult {
  if (input.template.sport === "run") return generateRunningCatalogWindow(input);
  const raw = input.priorDecision?.programme as ProgrammeCursor | undefined;
  const valid = raw?.templateID === input.template.id && Number.isInteger(raw.weekIndex)
    && raw.weekIndex >= 1 && raw.weekIndex <= input.template.weeks.length
    && typeof raw.weekAnchor === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw.weekAnchor)
    && Number.isFinite(new Date(raw.weekAnchor).getTime())
    && typeof raw.episodeStart === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw.episodeStart)
    && Number.isFinite(new Date(raw.episodeStart).getTime())
    && new Date(raw.episodeStart) >= new Date(raw.weekAnchor) && new Date(raw.episodeStart) < addDays(new Date(raw.weekAnchor), 7) && ["active", "completed"].includes(raw.status);
  if (raw && !valid) {
    console.error("[planning] catalog_programme_failed", { operation: "generate", category: "invalid_cursor" });
    throw new Error("The training programme cursor is invalid. Choose a current programme before rebuilding.");
  }
  const cursor: ProgrammeCursor = valid ? { ...raw } : {
    templateID: input.template.id, weekIndex: 1, weekAnchor: key(monday(input.createdAt)), episodeStart: key(day(input.createdAt)), status: "active",
  };
  let outcome: ProgrammeOutcome = valid ? "same_week" : "initial";
  const today = day(input.now);
  const anchor = new Date(cursor.weekAnchor);
  const elapsed = today >= addDays(anchor, 7);
  if (cursor.status === "completed") outcome = "completed";
  else if (elapsed) {
    const prescribed = instantiateCatalogWeek(input.template, cursor.weekIndex, anchor, new Date(cursor.episodeStart), input.goal);
    const completed = new Set(input.evidence.filter((row) => {
      const prescription = record(row.prescription);
      return row.status === "completed" && row.scheduledDate >= anchor && row.scheduledDate < addDays(anchor, 7)
        && prescription?.templateID === input.template.id && prescription.weekIndex === cursor.weekIndex
        && row.completions.some((completion) => ["completed", "feltEasy"].includes(completion.completionQuality)
          && completion.durationSeconds != null && completion.durationSeconds >= row.durationSeconds * 0.8);
    }).map((row) => record(row.prescription)?.workoutID));
    const adequate = prescribed.length > 0 && prescribed.filter((row) => completed.has(row.prescription.workoutID)).length >= Math.ceil(prescribed.length * 0.8);
    const advance = adequate && input.readyToAdvance && !input.explicitDifficulty;
    if (advance && cursor.weekIndex === input.template.weeks.length) {
      cursor.status = "completed";
      outcome = "completed";
    } else {
      if (advance) cursor.weekIndex += 1;
      outcome = advance ? "advanced" : "repeated";
      // Evaluate only the elapsed episode. Never fast-forward over untrained weeks.
      cursor.weekAnchor = key(monday(today));
      cursor.episodeStart = key(today);
    }
  }
  const currentAnchor = new Date(cursor.weekAnchor);
  const workouts = cursor.status === "completed" ? [] : [0, 1].flatMap((offset) =>
    instantiateCatalogWeek(input.template, cursor.weekIndex + offset, addDays(currentAnchor, offset * 7), today, input.goal)
      .map((workout) => ({ ...workout, prescription: { ...workout.prescription,
        programmeWeekAnchor: key(addDays(currentAnchor, offset * 7)), provisional: offset > 0 } }))
  );
  return {
    phase: cursor.status === "completed" ? "maintenance" : phaseForGoal(input.goal, input.now),
    summary: input.template.summary,
    workouts: workouts.map((workout) => applyRunningBenchmark(workout, input.goal.constraints, input.now)),
    engineDecision: {
      runningBenchmark: runningBenchmarkDecision(input.goal.constraints, input.now),
      source: "trainingPlanCatalog", templateID: input.template.id,
      catalogPolicyVersion: CATALOG_POLICY_VERSION, programme: cursor, programmeOutcome: outcome,
      futureWeeksProvisional: true, frequencyOutcome: workouts.length < input.goal.daysPerWeekTarget * 2 ? "source_limited" : "as_requested", windowCheckedOn: key(today),
    },
  };
}
export function record(value: unknown): Record<string, unknown> | undefined {
  return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
export function day(value: Date): Date { return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate())); }
export function monday(value: Date): Date { const date = day(value); return addDays(date, -((date.getUTCDay() + 6) % 7)); }
export function addDays(value: Date, amount: number): Date { return new Date(value.getTime() + amount * 86_400_000); }
function key(value: Date): string { return value.toISOString().slice(0, 10); }

/** Earned source exposure is independent of calendar frequency and projected dates. */
function generateRunningCatalogWindow(input: Parameters<typeof generateCatalogWindow>[0]): PlanGenerationResult {
  const today = day(input.now);
  const raw = record(input.priorDecision?.programme);
  const initial = !raw;
  const sourceIndex = raw ? Number(raw.weekIndex) : 1;
  const source = input.template.weeks[sourceIndex - 1];
  const validDate = (value: unknown): value is string => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && Number.isFinite(new Date(value).getTime()) && key(new Date(value)) === value;
  if (raw && (raw.templateID !== input.template.id || !Number.isInteger(sourceIndex) || !source || !validDate(raw.weekAnchor)
      || !validDate(raw.episodeStart) || new Date(String(raw.weekAnchor)).getUTCDay() !== 1
      || new Date(String(raw.weekAnchor)) > today || new Date(String(raw.episodeStart)) < new Date(String(raw.weekAnchor))
      || new Date(String(raw.episodeStart)) >= addDays(new Date(String(raw.weekAnchor)), 7) || new Date(String(raw.episodeStart)) > today
      || raw.sourceWeekStartedOn != null && (!validDate(raw.sourceWeekStartedOn) || new Date(String(raw.sourceWeekStartedOn)) > new Date(String(raw.episodeStart)))
      || !["active", "completed"].includes(String(raw.status)) || raw.status === "completed" && sourceIndex !== input.template.weeks.length)) {
    console.error("[planning] catalog_programme_failed", { operation: "generate", category: "invalid_cursor" });
    throw new Error("The training programme cursor is invalid. Choose a current programme before rebuilding.");
  }
  const cursor = {
    templateID: input.template.id, weekIndex: sourceIndex,
    weekAnchor: raw ? String(raw.weekAnchor) : key(monday(today)),
    episodeStart: raw ? String(raw.episodeStart) : key(today),
    sourceWeekStartedOn: validDate(raw?.sourceWeekStartedOn) ? raw.sourceWeekStartedOn : raw ? String(raw.episodeStart) : key(today),
    status: (raw?.status ?? "active") as "active" | "completed",
  };
  const state = input.athleteState ?? computeAthleteTrainingState({ activities: [], plannedWorkouts: [], readiness: [], now: input.now });
  const authoredWalkRun = input.template.weeks[0].workouts.some((row) => row.kind === "walkRun" && !row.isOptional);
  const programme = input.runWalkProgramme ?? evaluateRunWalkProgramme({
    previous: input.priorDecision?.runWalkProgramme, enabled: !authoredWalkRun && input.goal.baselineContext !== "currentlyActive", now: input.now,
    evidence: input.evidence as PrescribedRunningEvidence[], explicitDifficulty: input.explicitDifficulty || !input.readyToAdvance,
    athleteState: state, initialSessionSeconds: Math.min(1500, input.goal.maxSessionMinutes * 60), sessionCapSeconds: input.goal.maxSessionMinutes * 60,
  }).state;
  const budget = runningDoseBudget(input.goal, state, programme, true);
  const requiredFor = (index: number) => input.template.weeks[index - 1].workouts.filter((row) => !row.isOptional && row.kind !== "race" && row.durationSeconds > 0);
  const skipRaceContextWeeks = () => {
    while (cursor.status === "active" && requiredFor(cursor.weekIndex).length === 0) {
      if (cursor.weekIndex === input.template.weeks.length) cursor.status = "completed";
      else { cursor.weekIndex++; cursor.sourceWeekStartedOn = key(today); }
    }
  };
  skipRaceContextWeeks();
  const completed = new Set(input.evidence.filter((row) => {
    const prescription = record(row.prescription);
    return row.scheduledDate >= new Date(cursor.sourceWeekStartedOn) && prescription?.templateID === input.template.id
      && prescription.weekIndex === cursor.weekIndex && prescription.sourceExposureEligible !== false
      && adequateRunningEvidence(row as PrescribedRunningEvidence, undefined, input.now);
  }).map((row) => String(record(row.prescription)?.workoutID)));
  let outcome: ProgrammeOutcome = initial ? "initial" : "same_week";
  const elapsed = today >= addDays(new Date(cursor.weekAnchor), 7);
  const authoredIDs = requiredFor(cursor.weekIndex).map((row) => row.id);
  if (cursor.status === "completed") outcome = "completed";
  else if (elapsed) {
    const adequate = authoredIDs.filter((id) => completed.has(id)).length >= Math.ceil(authoredIDs.length * .8);
    if (adequate && input.readyToAdvance && !input.explicitDifficulty && programme?.status !== "active") {
      if (cursor.weekIndex === input.template.weeks.length) { cursor.status = "completed"; outcome = "completed"; }
      else { cursor.weekIndex++; cursor.sourceWeekStartedOn = key(today); completed.clear(); outcome = "advanced"; }
    } else outcome = "repeated";
    cursor.weekAnchor = key(monday(today));
    cursor.episodeStart = key(today);
  }
  skipRaceContextWeeks();
  if (cursor.status === "completed") outcome = "completed";
  const sourceRemainingWeeks = input.template.weeks.slice(cursor.weekIndex - 1).reduce((total, week, index) => {
    const ids = week.workouts.filter((row) => !row.isOptional && row.kind !== "race" && row.durationSeconds > 0).map((row) => row.id);
    const needed = Math.max(0, Math.ceil(ids.length * .8) - (index === 0 ? ids.filter((id) => completed.has(id)).length : 0));
    return total + (ids.length ? Math.max(1, Math.ceil(needed / input.goal.daysPerWeekTarget)) : 0);
  }, 0);
  const remainingWeeks = sourceRemainingWeeks + (programme?.status === "active" ? (7 - programme.stageIndex) * Math.max(1, Math.ceil(3 / input.goal.daysPerWeekTarget)) : 0);
  // A minimum exposure calendar estimate is not a promised completion date.
  const timelineConflict = input.goal.type === "eventPreparation" && input.goal.targetDate && cursor.status !== "completed"
    && new Date(input.goal.targetDate).getTime() < today.getTime() + remainingWeeks * 7 * 86400000;
  if (initial && timelineConflict) throw new ProgrammeTimelineError();
  const pending = requiredFor(cursor.weekIndex).filter((row) => !completed.has(row.id)).map((row) => row.id);
  let consumed = 0, scheduleNeedsReview = false, conservativeRecipeNeedsReview = false;
  const workouts: import("./types.js").PlannedWorkoutDraft[] = [];
  if (cursor.status !== "completed") for (const offset of [0, 1]) {
    const anchor = addDays(new Date(cursor.weekAnchor), offset * 7);
    // Validate source-supported frequency, then fill its accepted calendar slots.
    instantiateCatalogWeek(input.template, cursor.weekIndex, anchor, today, input.goal);
    const sourceRows = requiredFor(cursor.weekIndex);
    const weekday = (value: string) => ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].indexOf(value.slice(0, 3).toLowerCase());
    const selectedDays = [...new Set(input.goal.preferredDays.map(weekday).filter((index) => index >= 0))].slice(0, input.goal.daysPerWeekTarget);
    for (const index of [...sourceRows.map((row) => weekday(row.dayLabel)), ...Array.from({ length: 7 }, (_, index) => index)]) {
      if (selectedDays.length >= input.goal.daysPerWeekTarget) break;
      if (index >= 0 && !selectedDays.includes(index)) selectedDays.push(index);
    }
    const slots = selectedDays.sort((left, right) => left - right).map((offset) => addDays(anchor, offset)).filter((date) => date >= today)
      .map((date) => toPlannedWorkout(sourceRows[0], input.template.sport, date, input.template.id, cursor.weekIndex));
    const selected = pending.slice(consumed, consumed + slots.length);
    consumed += selected.length;
    const ids: Array<string | undefined> = [...selected, ...Array(Math.max(0, slots.length - selected.length)).fill(undefined)];
    const ordered = arrangeSourceRoles(ids, slots.map((row) => row.scheduledDate), requiredFor(cursor.weekIndex));
    if (!ordered) scheduleNeedsReview = true;
    for (const [slotIndex, slot] of slots.entries()) {
      const id = (ordered ?? ids)[slotIndex];
      // Reconstruct the selected authored work at this slot; unissued IDs remain pending.
      const authored = id ? toPlannedWorkout(requiredFor(cursor.weekIndex).find((row) => row.id === id)!, input.template.sport, slot.scheduledDate, input.template.id, cursor.weekIndex) : undefined;
      const doseAdaptation = shortRunningSessionsAllowed(input.goal) || programme != null;
      const doseCeiling = authoredWalkRun || !doseAdaptation ? input.goal.maxSessionMinutes : authored?.stimulus === "longEndurance"
        ? budget?.longSessionCeilingMinutes ?? input.goal.maxSessionMinutes : budget?.perSessionCeilingMinutes ?? input.goal.maxSessionMinutes;
      const acceptedSeconds = authored ? Math.min(authored.durationSeconds, input.goal.maxSessionMinutes * 60) : slot.durationSeconds;
      let workout = authored ? resizeTimedRunningWorkout(authored, Math.min(acceptedSeconds, doseCeiling * 60)) : slot;
      let sourceEligible = authored != null && (shortRunningSessionsAllowed(input.goal) || workout.durationSeconds === acceptedSeconds);
      if (programme?.status === "completed" && input.goal.riskTolerance === "conservative" && !shortRunningSessionsAllowed(input.goal)
          && authored && workout.durationSeconds < acceptedSeconds) conservativeRecipeNeedsReview = true;
      if (!authored || programme?.status === "active") {
        const ratio = programme?.status === "active" ? RUN_WALK_LADDER[programme.stageIndex] : undefined;
        const generated = buildRunningWorkout({ scheduledDate: slot.scheduledDate, modality: "run", stimulus: "easyAerobic", athleteState: state,
          durationMinutes: Math.min(workout.durationSeconds, programme?.status === "active" ? programme.sessionTotalSeconds : workout.durationSeconds, input.goal.maxSessionMinutes * 60) / 60,
          allowShortSession: true, baselineContext: programme?.status === "active" ? "returningToTraining" : "currentlyActive", runWalk: programme?.status === "active" || authoredWalkRun,
          runWalkStage: programme?.status === "active" ? { runSeconds: ratio?.[0] ?? programme.sessionTotalSeconds, walkSeconds: ratio?.[1] ?? 0, continuousTrial: !ratio } : undefined });
        const { summary, purpose, guideCue, effortLabel, steps, ...sourceMetadata } = workout.prescription;
        workout = { ...generated, intensityModel: "catalog", prescription: { ...generated.prescription, ...sourceMetadata,
          authoredContext: { summary, purpose, guideCue, effortLabel },
          runWalk: generated.prescription.runWalk, workoutKind: generated.prescription.workoutKind }, blocks: generated.blocks };
        sourceEligible = false;
      }
      const event = input.goal.type === "eventPreparation" && input.goal.targetDate ? day(new Date(input.goal.targetDate)) : undefined;
      if (event && workout.scheduledDate >= event) continue;
      if (phaseForGoal(input.goal, workout.scheduledDate) === "taper") {
        workout = resizeTimedRunningWorkout(workout, Math.min(workout.durationSeconds, Math.max(Math.min(1500, workout.durationSeconds), Math.floor(workout.durationSeconds * .8))));
      }
      const finalEasy = event && event.getTime() - workout.scheduledDate.getTime() <= 48 * 3600000;
      const reportedHard = (state.modalityBreakdown.run as { lastReportedHardAt?: string } | undefined)?.lastReportedHardAt;
      const hardAt = Math.max(state.lastHardWorkoutAt?.getTime() ?? 0, reportedHard ? new Date(reportedHard).getTime() : 0);
      if (finalEasy || (workout.stimulus === "longEndurance" || Number(workout.prescription.qualitySeconds ?? 0) > 0) && workout.scheduledDate.getTime() - hardAt < 48 * 3600000) {
        workout = resizeTimedRunningWorkout(workout, workout.durationSeconds, true);
        sourceEligible = false;
      }
      workout = { ...workout, prescription: { ...workout.prescription, source: "trainingPlanCatalog", templateID: input.template.id,
        weekIndex: cursor.weekIndex, sourceWeekStartedOn: cursor.sourceWeekStartedOn, sourceExposureEligible: sourceEligible,
        programmeWeekAnchor: key(anchor), provisional: offset > 0, filler: !authored } };
      workouts.push(stampIssuedRunningDose(applyRunningBenchmark(synchronizeRunningPrescription(workout), input.goal.constraints, input.now), programme));
    }
  }
  if (shortRunningSessionsAllowed(input.goal) && budget) {
    for (const anchor of [monday(today), addDays(monday(today), 7)]) {
      const week = workouts.filter((row) => row.scheduledDate >= anchor && row.scheduledDate < addDays(anchor, 7));
      const total = week.reduce((sum, row) => sum + row.durationSeconds, 0);
      const target = budget.targetWeeklyMinutes * 60 * week.length / budget.sessionsPerWeek;
      if (total > target) for (const row of week) {
        const resized = resizeTimedRunningWorkout(row, Math.floor(row.durationSeconds * target / total));
        workouts[workouts.indexOf(row)] = stampIssuedRunningDose(resized, programme);
      }
    }
  }
  let qualityNeedsReview = scheduleNeedsReview;
  // Authored roles retain their order; lighter replacements do not earn source credit.
  for (let index = 0; index < workouts.length; index++) {
    let row = workouts[index];
    if (row.stimulus !== "longEndurance" && Number(row.prescription.qualitySeconds ?? 0) <= 0 && !["threshold", "speed"].includes(row.stimulus)) continue;
    const otherKey = workouts.findIndex((other, otherIndex) => otherIndex !== index && (other.stimulus === "longEndurance" || Number(other.prescription.qualitySeconds ?? 0) > 0)
      && Math.abs(other.scheduledDate.getTime() - row.scheduledDate.getTime()) < 48 * 3600000);
    const weekStart = monday(row.scheduledDate), weekEnd = addDays(weekStart, 7);
    const weekRows = workouts.filter((other) => other.scheduledDate >= weekStart && other.scheduledDate < weekEnd);
    const run = state.modalityBreakdown.run as { minutes?: number; baselineEstablished?: boolean } | undefined;
    const baselineSeconds = run?.baselineEstablished && (run.minutes ?? 0) > 0 ? run.minutes! / 4 * 60
      : weekRows.reduce((sum, other) => sum + other.durationSeconds, 0);
    const alreadyPrescribed = workouts.slice(0, index).filter((other) => other.scheduledDate >= weekStart && other.scheduledDate < weekEnd)
      .reduce((sum, other) => sum + Number(other.prescription.qualitySeconds ?? 0), 0);
    const allowance = Math.min(isShortSourceRepetition(row) ? 270 : Number((row.prescription.intensitySeconds as Record<string, unknown> | undefined)?.speed ?? 0) > 0 ? 720 : 1200, Math.max(0, baselineSeconds * .1 - alreadyPrescribed));
    const isQuality = Number(row.prescription.qualitySeconds ?? 0) > 0 || ["threshold", "speed"].includes(row.stimulus);
    if (otherKey >= 0 && (isQuality || otherKey < index) || isQuality && state.fatigueRisk !== "low") {
      row = resizeTimedRunningWorkout(row, row.durationSeconds, true);
      row = { ...row, prescription: { ...row.prescription, sourceExposureEligible: false } };
      workouts[index] = stampIssuedRunningDose(row, programme);
    } else if (isQuality) {
      const recipe = limitRunningQuality(row, allowance);
      if (recipe) workouts[index] = stampIssuedRunningDose(applyRunningBenchmark(recipe, input.goal.constraints, input.now), programme);
      else {
        qualityNeedsReview = true;
        const easy = resizeTimedRunningWorkout(row, row.durationSeconds, true);
        workouts[index] = stampIssuedRunningDose({ ...easy, prescription: { ...easy.prescription, sourceExposureEligible: false } }, programme);
      }
    }
  }
  if (initial && qualityNeedsReview) throw new ProgrammeConstraintError();
  if (initial && programme?.status !== "active") {
    for (const anchor of [monday(today), addDays(monday(today), 7)]) {
      assertAuthoredRunningDose(budget, workouts.filter((row) => row.scheduledDate >= anchor && row.scheduledDate < addDays(anchor, 7))
        .reduce((sum, row) => sum + row.durationSeconds / 60, 0), shortRunningSessionsAllowed(input.goal));
    }
    if (budget?.capacityKnown && !authoredWalkRun && !shortRunningSessionsAllowed(input.goal)
      && workouts.some((row) => row.durationSeconds / 60 > (row.stimulus === "longEndurance" ? budget.longSessionCeilingMinutes : budget.perSessionCeilingMinutes) / (input.goal.riskTolerance === "conservative" ? 1 : input.goal.riskTolerance === "stretch" ? 1.15 : 1.10) * 1.5)) {
      throw new RunningScheduleError("session_capacity");
    }
  }
  const recipeNeedsReview = qualityNeedsReview || conservativeRecipeNeedsReview;
  return { phase: cursor.status === "completed" && !input.goal.targetDate ? "maintenance" : phaseForGoal(input.goal, input.now), summary: input.template.summary, workouts,
    engineDecision: { runningBenchmark: runningBenchmarkDecision(input.goal.constraints, input.now), source: "trainingPlanCatalog", templateID: input.template.id,
      catalogPolicyVersion: CATALOG_POLICY_VERSION, runningDosePolicy: RUNNING_DOSE_POLICY, programme: cursor, programmeOutcome: outcome, runWalkProgramme: programme ?? null,
      preparationOnly: true,
      authoredRaceContext: { prescription: "goal_context_only", workoutIDs: input.template.weeks.flatMap((week) => week.workouts.filter((row) => row.kind === "race").map((row) => row.id)) },
      nominalSourceWeeks: input.template.weeks.length, minimumRemainingCalendarWeeks: cursor.status === "completed" ? 0 : recipeNeedsReview ? null : remainingWeeks,
      minimumCalendarEstimateCondition: recipeNeedsReview ? "requires_recipe_fit" : "adequate_future_exposure",
      completedSourceWorkouts: requiredFor(cursor.weekIndex).filter((row) => completed.has(row.id)).length, programmeTimelineStatus: timelineConflict || recipeNeedsReview ? "needs_review" : "minimum_estimate",
      programmeDoseStatus: recipeNeedsReview ? "needs_review" : "supported",
      programmeReviewReason: conservativeRecipeNeedsReview ? "conservative_recipe_fit" : qualityNeedsReview ? "quality_or_schedule_fit" : null,
      programmeReviewAction: conservativeRecipeNeedsReview ? "allow_shorter_or_change_programme" : qualityNeedsReview ? "change_schedule_or_programme" : null, futureWeeksProvisional: true, frequencyOutcome: "as_requested", windowCheckedOn: key(today) } };
}

/** Reorder within the accepted dates; do not drop a required source quality role. */
function arrangeSourceRoles(ids: Array<string | undefined>, dates: Date[], source: import("../trainingPlans.js").TrainingPlanWorkout[]): Array<string | undefined> | undefined {
  const keyIDs = new Set(source.filter((row) => ["tempo", "interval", "fartlek", "hill", "longRun", "racePrep", "race"].includes(row.kind)).map((row) => row.id));
  const place = (remaining: Array<string | undefined>, chosen: Array<string | undefined>): Array<string | undefined> | undefined => {
    if (!remaining.length) return chosen;
    const tried = new Set<string | undefined>();
    for (let index = 0; index < remaining.length; index++) {
      const id = remaining[index]; if (tried.has(id)) continue; tried.add(id);
      if (id && keyIDs.has(id) && chosen.some((other, prior) => other && keyIDs.has(other)
          && dates[chosen.length].getTime() - dates[prior].getTime() < 48 * 3600000)) continue;
      const result = place(remaining.filter((_, candidate) => candidate !== index), [...chosen, id]);
      if (result) return result;
    }
    return undefined;
  };
  return place(ids, []);
}
