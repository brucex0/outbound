import type { Scenario } from "./scenarios.js";
export const CHECKS_VERSION = "running-payload-checks-v4";
export interface Finding { rule: string; severity: "error" | "warning"; workoutIds: string[]; evidence: string; }
export interface EvaluatedWindow { id: string; now: string; phase: string; programme?: Record<string, unknown>; workouts: any[]; }

/** Independent payload inspection; deliberately does not call planner limit helpers. */
export function inspectWindow(scenario: Scenario, window: EvaluatedWindow): Finding[] {
  const findings: Finding[] = [];
  const add = (rule: string, severity: Finding["severity"], rows: any[], evidence: string) => findings.push({ rule, severity, workoutIds: rows.map((row) => row.evaluationId), evidence });
  const required = window.workouts.filter((row) => row.prescription?.optional !== true);
  const now = new Date(window.now).getTime();
  const sessions = new Map<string, any[]>();
  const preferred = new Set((scenario.goal.preferredDays ?? []).map((name) => ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].indexOf(name.slice(0, 3))));
  for (const row of required) {
    const date = new Date(row.scheduledDate);
    const phases = row.blocks.flatMap((block: any) => block.steps);
    const sum = phases.reduce((total: number, phase: any) => total + (phase.durationSeconds ?? 0), 0);
    if (sum !== row.durationSeconds) add("PHASE_TOTAL", "error", [row], `Phase sum ${sum}s differs from total ${row.durationSeconds}s.`);
    if (phases.some((phase: any) => (phase.durationSeconds ?? 0) <= 0)) add("PHASE_POSITIVE_DURATION", "error", [row], "An executable timed phase has no positive duration.");
    for (const block of row.blocks) if (block.durationSeconds != null && block.steps.length && block.steps.reduce((total: number, phase: any) => total + (phase.durationSeconds ?? 0), 0) !== block.durationSeconds) add("BLOCK_TOTAL", "error", [row], "A block total differs from its explicit phases.");
    if (row.blocks.some((block: any) => (block.repeats ?? 1) > 1 && block.steps.length > 1)) add("REPEAT_REPRESENTATION", "warning", [row], "A repeat multiplier accompanies expanded phase rows; verify no double expansion.");
    if (row.durationSeconds > (scenario.goal.maxSessionMinutes ?? 45) * 60) add("SESSION_CAP", "error", [row], `Prescription ${row.durationSeconds}s exceeds requested cap ${(scenario.goal.maxSessionMinutes ?? 45) * 60}s.`);
    if (date.getTime() < now) add("NO_PAST_SLOT", "error", [row], "Prescription precedes the window's frozen day.");
    if (preferred.size && !preferred.has(date.getUTCDay())) add("PREFERRED_DAY", "error", [row], `UTC weekday ${date.getUTCDay()} is outside the requested days.`);
    const key = date.toISOString().slice(0, 10); sessions.set(key, [...(sessions.get(key) ?? []), row]);
    if (scenario.goal.baselineContext !== "currentlyActive" && row.modality === "run" && hardSeconds(row) > 0) add("BEGINNER_NO_QUALITY", "error", [row], "Starting/returning context contains a hard running phase.");
    if (scenario.goal.baselineContext !== "currentlyActive" && row.modality === "run" && !phases.some((phase: any) => phase.kind === "walk")) add("BEGINNER_EXPLICIT_WALK", "error", [row], "Beginner run/walk is not represented by an executable walking phase.");
    if (scenario.readiness.some((entry) => entry.illnessOrPain) && date.getTime() < now + 7 * 86_400_000 && hardSeconds(row) > 0) add("PAIN_NO_NEAR_QUALITY", "error", [row], "Hard work falls within the assumed seven-day active-pain review window.");
    if (scenario.catalogue && row.prescription?.source !== "trainingPlanCatalog") add("CATALOGUE_SOURCE", "error", [row], "A selected programme workout has lost its catalogue source.");
    const derived = phases.filter((phase: any) => phase.target?.paceEstimatePolicy != null);
    const raw = scenario.goal.constraints?.runningBenchmark as Record<string, unknown> | undefined;
    const benchmarkDate = typeof raw?.date === "string" ? new Date(raw.date) : null;
    const explicit = raw?.activity === "run" && raw.maximalEffort === true && ["race", "timeTrial"].includes(String(raw.source))
      && typeof raw.distanceMeters === "number" && raw.distanceMeters >= 1500 && raw.distanceMeters <= 30000
      && typeof raw.durationSeconds === "number" && Number.isFinite(raw.durationSeconds) && raw.durationSeconds > 0
      && benchmarkDate != null && Number.isFinite(benchmarkDate.getTime()) && benchmarkDate.toISOString().slice(0, 10) === raw.date
      && benchmarkDate.getTime() <= now && now - benchmarkDate.getTime() <= 84 * 86400000;
    const provenance = row.prescription?.runningFitness;
    if (derived.length && (!explicit || provenance?.status !== "eligible" || provenance?.estimateKind !== "reported_maximal_performance"
        || derived.some((phase: any) => phase.target.paceEstimatePolicy !== provenance?.policyVersion))) {
      add("GOAL_NOT_CURRENT_FITNESS", "error", [row], "Derived phase pace lacks a fresh explicit maximal benchmark input and matching runningFitness/paceEstimatePolicy provenance.");
    } else if (row.intensityModel === "pace" && row.prescription?.eventTargetPaceSecondsPerKilometer != null && !explicit) {
      add("GOAL_NOT_CURRENT_FITNESS", "error", [row], "Goal pace is used as current-fitness pace without explicit benchmark evidence.");
    }
  }
  for (const rows of sessions.values()) if (rows.length > 1) add("NO_DUPLICATE_REQUIRED_SLOT", "error", rows, "Multiple required prescriptions share a calendar date.");
  const adverse = scenario.readiness.some((entry) => entry.illnessOrPain || entry.energy <= 2 || entry.soreness >= 4);
  for (let week = 0; week < 2; week++) {
    const rows = required.filter((row) => { const date = new Date(row.scheduledDate).getTime(); return date >= now + week * 7 * 86_400_000 && date < now + (week + 1) * 7 * 86_400_000; });
    if (!adverse && rows.length !== scenario.goal.daysPerWeekTarget) add("REQUESTED_FREQUENCY", "error", rows, `Week ${week + 1} has ${rows.length} required sessions versus ${scenario.goal.daysPerWeekTarget} requested.`);
    const checkpointShift = now - scenario.now.getTime();
    const baseline = scenario.activities.filter((item) => {
      const shifted = item.startedAt.getTime() + checkpointShift;
      return item.type === "run" && shifted >= now - 28 * 86_400_000 && shifted <= now;
    }).reduce((sum, item) => sum + (item.durationSecs ?? 0), 0) / 4;
    const quality = rows.reduce((sum, row) => sum + hardSeconds(row), 0);
    if (baseline > 0 && quality > baseline * .20) add("QUALITY_WEEK_BUDGET_REVIEW", "warning", rows.filter((row) => hardSeconds(row) > 0), `Weekly quality ${quality}s exceeds this evaluator's 20% baseline-running-time review threshold (${Math.round(baseline * .20)}s). This is a product review heuristic.`);
    const volume = rows.filter((row) => row.modality === "run").reduce((sum, row) => sum + row.durationSeconds, 0);
    if (baseline >= 3600 && !adverse && volume > baseline * 1.4) add("VOLUME_JUMP_REVIEW", "warning", rows, `Weekly run time ${volume}s exceeds 140% of synthetic baseline ${Math.round(baseline)}s; inspect dose/feasibility rather than assuming a universal injury threshold.`);
  }
  const quality = required.filter((row) => hardSeconds(row) > 0).sort((a, b) => new Date(a.scheduledDate).getTime() - new Date(b.scheduledDate).getTime());
  for (let index = 1; index < quality.length; index++) if (new Date(quality[index].scheduledDate).getTime() - new Date(quality[index - 1].scheduledDate).getTime() < 48 * 3_600_000) add("QUALITY_SPACING", "error", quality.slice(index - 1, index + 1), "Quality workouts are less than 48 hours apart.");
  for (const hard of quality) for (const long of required.filter((row) => row.stimulus === "longEndurance")) if (hard !== long && Math.abs(new Date(hard.scheduledDate).getTime() - new Date(long.scheduledDate).getTime()) < 48 * 3_600_000) add("QUALITY_LONG_RECOVERY_REVIEW", "warning", [hard, long], "Quality and long-endurance work are less than 48 hours apart; inspect recovery spacing.");
  return findings;
}
export function hardSeconds(workout: any): number {
  return workout.blocks.flatMap((block: any) => block.steps).filter((phase: any) => ["threshold", "speed", "tempo", "interval", "hill", "race", "racePrep", "fartlek", "work"].includes(phase.kind)
    || (typeof phase.target?.rpe === "number" ? phase.target.rpe : phase.target?.rpe?.[0] ?? 0) >= 6)
    .reduce((sum: number, phase: any) => sum + (phase.durationSeconds ?? 0), 0);
}
