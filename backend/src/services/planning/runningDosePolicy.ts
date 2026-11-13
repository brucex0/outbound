import type { GeneratePlanInput } from "./generator.js";
import type { AthleteTrainingStateSnapshot } from "./types.js";
import type { RunWalkProgramme } from "./runWalkProgramme.js";
import { retainedIntakeBaseline } from "./intakeBaseline.js";

export const RUNNING_DOSE_POLICY = "running-dose-v5";
export class RunningScheduleError extends Error {
  readonly code: "running_baseline_required" | "running_schedule_conflict";
  constructor(readonly category: "session_minimum" | "frequency_capacity" | "session_capacity" | "baseline_required") {
    super(category === "baseline_required" ? "Enter your recent weekly running time, or choose Starting out or Returning after a break."
      : "This schedule exceeds the running time currently supported by the plan. Choose fewer running days or explicitly allow shorter sessions.");
    this.code = category === "baseline_required" ? "running_baseline_required" : "running_schedule_conflict";
  }
}
export class ProgrammeTimelineError extends Error {
  readonly code = "programme_timeline_conflict";
  constructor() { super("This programme cannot fit your race date at the selected schedule. Choose a later date or a different programme."); }
}
export class ProgrammeConstraintError extends Error {
  readonly code = "programme_constraints_conflict";
  constructor() { super("This programme’s quality work does not fit your current running capacity. Choose a different programme or update your running schedule."); }
}
export interface RunningDoseBudget {
  basis: "prescribed_starter" | "completed_trial" | "observed_run_history" | "self_reported_provisional" | "sparse_fallback";
  baselineWeeklyMinutes: number;
  targetWeeklyMinutes: number;
  perSessionCeilingMinutes: number;
  longSessionCeilingMinutes: number;
  representativeLongMinutes: number;
  ordinarySessionMinutes: number;
  minimumMinutes: number;
  sessionsPerWeek: number;
  capacityKnown: boolean;
  observedLongSessionCeilingMinutes: number;
  reportedCapacityApplied: boolean;
}
export function shortRunningSessionsAllowed(goal: { constraints?: Record<string, unknown> }): boolean {
  return goal.constraints?.shortRunSessions === true || goal.constraints?.shortRunSessions === "true";
}

/** Original admission/dose heuristics, not validated injury thresholds. A cap is a ceiling. */
export function runningDoseBudget(goal: GeneratePlanInput["goal"], state: AthleteTrainingStateSnapshot,
  programme?: RunWalkProgramme, authored = false, actualSessionsPerWeek?: number): RunningDoseBudget | undefined {
  if (!goal.activities.includes("run")) return undefined;
  const short = shortRunningSessionsAllowed(goal);
  if (!authored && !short && goal.maxSessionMinutes < 25) throw new RunningScheduleError("session_minimum");
  const sessionsPerWeek = actualSessionsPerWeek ?? Math.max(1, Math.ceil(goal.daysPerWeekTarget / Math.max(1, goal.activities.length)));
  const run = state.modalityBreakdown.run as { minutes?: number; baselineEstablished?: boolean; typicalDoseSessionMinutes?: number; representativeLongMinutes?: number } | undefined;
  const starter = programme?.status === "active" || !programme && goal.baselineContext !== "currentlyActive";
  const observed = run?.baselineEstablished === true && typeof run.minutes === "number" && run.minutes > 0;
  const trial = programme?.status === "completed";
  const baseline = retainedIntakeBaseline(goal.constraints);
  if (!starter && !observed && !trial && goal.baselineContext === "currentlyActive" && goal.activities.length === 1
    && baseline?.source === "self_reported" && (baseline.recentSessionsPerWeek === 0 || !baseline.recentWeeklyRunMinutes)) throw new RunningScheduleError("baseline_required");
  const provisional = !starter && !observed && !trial && goal.baselineContext === "currentlyActive"
    && goal.activities.length === 1 && baseline?.source === "self_reported" && baseline.recentSessionsPerWeek > 0 && baseline.recentWeeklyRunMinutes != null;
  const basis = starter ? "prescribed_starter" : observed ? "observed_run_history" : trial ? "completed_trial" : provisional ? "self_reported_provisional" : "sparse_fallback";
  const capacityKnown = basis !== "sparse_fallback";
  const baselineWeeklyMinutes = starter ? 75 : observed ? run!.minutes! / 4
    : trial ? programme.completedTrialWeeklyMinutes! : provisional ? baseline!.recentWeeklyRunMinutes! : sessionsPerWeek * Math.min(30, goal.maxSessionMinutes);
  const sessionEvidence = starter ? (programme?.sessionTotalSeconds ?? Math.min(1500, goal.maxSessionMinutes * 60)) / 60
    : observed && run?.typicalDoseSessionMinutes != null ? run.typicalDoseSessionMinutes
      : trial ? programme.completedTrialTotalSeconds! / 60 : provisional ? Math.min(baseline!.comfortableDurationMinutes, baselineWeeklyMinutes / baseline!.recentSessionsPerWeek) : Math.min(30, goal.maxSessionMinutes);
  const minimumMinutes = authored ? 0 : short ? 10 : 25;
  const minimumWeekly = minimumMinutes * sessionsPerWeek;
  // A confirmed existing 15min programme cannot grow merely because its cap increased.
  if (!authored && starter && sessionEvidence < minimumMinutes) throw new RunningScheduleError("session_minimum");
  if (provisional && minimumWeekly > baselineWeeklyMinutes) throw new RunningScheduleError("frequency_capacity");
  if (provisional && minimumMinutes > sessionEvidence) throw new RunningScheduleError("session_capacity");
  // A minimum weekly dose 50% or more above the reference requires explicit schedule review.
  if (capacityKnown && minimumWeekly >= baselineWeeklyMinutes * 1.5) throw new RunningScheduleError("frequency_capacity");
  if (capacityKnown && minimumMinutes > sessionEvidence * 1.5) throw new RunningScheduleError("session_capacity");
  // Preferences alter supported growth, never a recurring percentage decay.
  const growth = goal.riskTolerance === "conservative" ? 1 : goal.riskTolerance === "stretch" ? 1.15 : 1.10;
  const targetWeeklyMinutes = Math.min(goal.maxSessionMinutes * sessionsPerWeek,
    starter ? Math.max(minimumWeekly, 75) : provisional ? baselineWeeklyMinutes : capacityKnown ? Math.max(minimumWeekly, baselineWeeklyMinutes * growth) : baselineWeeklyMinutes);
  const perSessionCeilingMinutes = Math.min(goal.maxSessionMinutes,
    Math.max(minimumMinutes, starter || !capacityKnown || provisional ? sessionEvidence : sessionEvidence * growth));
  const representativeLongMinutes = observed ? run?.representativeLongMinutes ?? sessionEvidence : sessionEvidence;
  const observedLongSessionCeilingMinutes = Math.min(goal.maxSessionMinutes, Math.max(minimumMinutes, starter || !capacityKnown || provisional ? sessionEvidence : representativeLongMinutes * growth));
  // A single-session capacity answer can widen a long slot, only within the
  // unchanged observed weekly budget. It is not evidence of repeated weekly dose.
  // Mixed-sport answers cannot establish specifically running capacity.
  const reportedCapacity = (observed || provisional) && !starter && !authored && goal.baselineContext === "currentlyActive"
    && goal.activities.length === 1 && baseline?.source === "self_reported"
    && baseline.recentSessionsPerWeek > 0 ? baseline.comfortableDurationMinutes : 0;
  const longSessionCeilingMinutes = Math.min(goal.maxSessionMinutes, Math.max(observedLongSessionCeilingMinutes, reportedCapacity));
  const reportedCapacityApplied = longSessionCeilingMinutes > observedLongSessionCeilingMinutes;
  return { basis, baselineWeeklyMinutes, targetWeeklyMinutes, perSessionCeilingMinutes, longSessionCeilingMinutes, representativeLongMinutes, minimumMinutes, sessionsPerWeek, capacityKnown,
    observedLongSessionCeilingMinutes, reportedCapacityApplied,
    ordinarySessionMinutes: Math.min(perSessionCeilingMinutes, Math.max(minimumMinutes, Math.floor(targetWeeklyMinutes / sessionsPerWeek))) };
}

export function assertAuthoredRunningDose(budget: RunningDoseBudget | undefined, minutes: number, allowsShorter: boolean): void {
  if (budget?.capacityKnown && !allowsShorter && minutes >= budget.baselineWeeklyMinutes * 1.5) throw new RunningScheduleError("frequency_capacity");
}
