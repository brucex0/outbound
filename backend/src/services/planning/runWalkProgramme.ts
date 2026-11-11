import { createHash } from "node:crypto";
import { unexpectedRunningEffort } from "./sessionEffort.js";
import type { AthleteTrainingStateSnapshot, PlannedWorkoutDraft, ReadinessForPlanning } from "./types.js";

export const RUN_WALK_POLICY = "prescribed-run-walk-v1";
export const RUN_WALK_LADDER = [[60, 90], [90, 90], [120, 90], [180, 90], [300, 90], [480, 90]] as const;
export interface RunWalkProgramme {
  policyVersion: typeof RUN_WALK_POLICY;
  stageIndex: number;
  stageStartedOn: string;
  episode: number;
  sessionTotalSeconds: number;
  status: "active" | "completed";
  completedTrialMainSeconds?: number;
  completedTrialTotalSeconds?: number;
  completedTrialWeeklyMinutes?: number;
}
export interface PrescribedRunningEvidence {
  id: string;
  scheduledDate: Date;
  modality: string;
  stimulus: string;
  durationSeconds: number;
  status: string;
  prescription: unknown;
  blocks: Array<{ blockType: string; stimulus?: string; durationSeconds?: number | null; sortOrder?: number; steps: Array<{ kind: string; durationSeconds?: number | null; target?: unknown; sortOrder?: number }> }>;
  edits?: Array<{ operation?: string }>;
  completions: Array<{ completedAt: Date; durationSeconds: number | null; completionQuality: string; perceivedEffort: number | null; performedAsIssued?: boolean | null; prescriptionRevision?: { programmeExposureEligible: boolean; sourceExposureEligible: boolean; stimulus: string } | null }>;
}
export type RunWalkOutcome = "initial" | "held" | "advanced" | "reset" | "completed" | "not_applicable";

/** Original exposure heuristics, not a measurement of continuous-running fitness. */
export function evaluateRunWalkProgramme(input: {
  previous?: unknown;
  enabled: boolean;
  now: Date;
  createdAt?: Date;
  evidence: PrescribedRunningEvidence[];
  athleteState: AthleteTrainingStateSnapshot;
  readiness?: ReadinessForPlanning;
  explicitDifficulty?: boolean;
  lastRecordedRunAt?: Date | null;
  initialSessionSeconds?: number;
  sessionCapSeconds?: number;
}): { state?: RunWalkProgramme; outcome: RunWalkOutcome } {
  const today = dayKey(input.now);
  const parsed = parseRunWalkProgramme(input.previous);
  const prior = parsed ? { ...parsed, sessionTotalSeconds: Math.min(parsed.sessionTotalSeconds, input.sessionCapSeconds ?? Infinity) } : undefined;
  if (!prior) return input.enabled ? { state: { policyVersion: RUN_WALK_POLICY, stageIndex: 0, stageStartedOn: today, episode: 0,
    sessionTotalSeconds: Math.min(input.initialSessionSeconds ?? 1500, input.sessionCapSeconds ?? Infinity), status: "active" }, outcome: "initial" } : { outcome: "not_applicable" };
  if (new Date(prior.stageStartedOn) > day(input.now)) {
    console.error("[planning] run_walk_programme_failed", { operation: "evaluate", category: "future_state" });
    throw new Error("The running programme state is invalid. Recreate the current plan before rebuilding.");
  }
  const stageRows = input.evidence.filter((row) => {
    const issued = record(record(row.prescription)?.runWalkProgramme);
    return issued?.policyVersion === RUN_WALK_POLICY && issued.stageIndex === prior.stageIndex && issued.episode === prior.episode
      && issued.stageStartedOn === prior.stageStartedOn;
  });
  const adequate = stageRows.filter((row) => adequateRunningEvidence(row, input.readiness, input.now, true));
  const completedAt = (row: PrescribedRunningEvidence) => Math.max(...row.completions.filter((completion) => completion.completedAt <= input.now).map((completion) => completion.completedAt.getTime()), 0);
  const latest = Math.max(new Date(prior.stageStartedOn).getTime(), ...adequate.map(completedAt));
  // Real running presence can prevent a false absence reset, but never advances a stage.
  const prescribedContinuity = input.evidence.filter((row) => row.modality === "run" && row.status === "completed")
    .flatMap((row) => row.completions).filter((completion) => completion.completedAt <= input.now
      && completion.durationSeconds != null && Number.isFinite(completion.durationSeconds) && completion.durationSeconds >= 300)
    .map((completion) => completion.completedAt.getTime());
  const continuity = Math.max(latest, input.lastRecordedRunAt?.getTime() ?? 0, ...prescribedContinuity);
  if (input.now.getTime() - continuity >= 14 * 86400000) {
    return { state: { policyVersion: RUN_WALK_POLICY, stageIndex: 0, stageStartedOn: today, episode: prior.episode + 1,
      sessionTotalSeconds: prior.status === "active" ? prior.sessionTotalSeconds : Math.min(input.initialSessionSeconds ?? 1500, input.sessionCapSeconds ?? Infinity), status: "active" }, outcome: "reset" };
  }
  if (prior.status === "completed") return { state: prior, outcome: "held" };
  const elapsed = day(input.now).getTime() - new Date(prior.stageStartedOn).getTime() >= 7 * 86400000;
  const readiness = input.readiness;
  const adverse = readiness && (readiness.illnessOrPain || readiness.energy <= 2 || readiness.soreness >= 4 || readiness.stress >= 4);
  // A fresh late difficulty report holds the stage; old reports do not penalize it forever.
  const difficulty = input.explicitDifficulty || stageRows.some((row) => row.completions.some((completion) => completion.completedAt <= input.now && completion.completedAt >= new Date(Math.max(new Date(prior.stageStartedOn).getTime(), input.now.getTime() - 7 * 86400000))
    && unexpectedRunningEffort({ ...completion, stimulus: completion.prescriptionRevision?.stimulus ?? row.stimulus }, readiness)));
  if (!elapsed || new Set(adequate.map((row) => row.id)).size < 3 || adverse || difficulty || input.athleteState.fatigueRisk !== "low") return { state: prior, outcome: "held" };
  if (prior.stageIndex < RUN_WALK_LADDER.length) {
    return { state: { ...prior, stageIndex: prior.stageIndex + 1, stageStartedOn: today, episode: prior.episode + 1 }, outcome: "advanced" };
  }
  // Completion describes adequately completed capped trials, never an invented 15min effort.
  const trials = adequate.filter((row) => record(record(row.prescription)?.runWalkProgramme)?.continuousTrial === true);
  if (new Set(trials.map((row) => row.id)).size < 3) return { state: prior, outcome: "held" };
  return { state: { ...prior, status: "completed", completedTrialMainSeconds: Math.min(...trials.map((row) => Number(record(record(row.prescription)?.issuedRunningDose)?.mainSeconds ?? 0))),
    completedTrialTotalSeconds: Math.min(...trials.map((row) => row.durationSeconds)),
    completedTrialWeeklyMinutes: trials.reduce((sum, row) => sum + row.durationSeconds / 60, 0) / Math.max(1, (day(input.now).getTime() - new Date(prior.stageStartedOn).getTime()) / (7 * 86400000)) }, outcome: "completed" };
}

export function parseRunWalkProgramme(value: unknown): RunWalkProgramme | undefined {
  if (value == null) return undefined;
  const raw = record(value);
  const valid = raw?.policyVersion === RUN_WALK_POLICY && Number.isInteger(raw.stageIndex) && Number(raw.stageIndex) >= 0 && Number(raw.stageIndex) <= RUN_WALK_LADDER.length
    && Number.isInteger(raw.episode) && Number(raw.episode) >= 0 && (raw.status === "active" || raw.status === "completed")
    && typeof raw.sessionTotalSeconds === "number" && Number.isFinite(raw.sessionTotalSeconds) && raw.sessionTotalSeconds > 0 && raw.sessionTotalSeconds <= 10800
    && typeof raw.stageStartedOn === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw.stageStartedOn) && Number.isFinite(new Date(raw.stageStartedOn).getTime())
    && new Date(raw.stageStartedOn).toISOString().slice(0, 10) === raw.stageStartedOn
    && (raw.status !== "completed" || raw.stageIndex === RUN_WALK_LADDER.length
      && typeof raw.completedTrialMainSeconds === "number" && raw.completedTrialMainSeconds > 0 && Number.isFinite(raw.completedTrialMainSeconds)
      && typeof raw.completedTrialTotalSeconds === "number" && raw.completedTrialTotalSeconds >= raw.completedTrialMainSeconds && Number.isFinite(raw.completedTrialTotalSeconds)
      && typeof raw.completedTrialWeeklyMinutes === "number" && raw.completedTrialWeeklyMinutes > 0 && Number.isFinite(raw.completedTrialWeeklyMinutes));
  if (!valid) {
    console.error("[planning] run_walk_programme_failed", { operation: "read", category: "invalid_state" });
    throw new Error("The running programme state is invalid. Recreate the current plan before rebuilding.");
  }
  return { policyVersion: RUN_WALK_POLICY, stageIndex: Number(raw.stageIndex), stageStartedOn: String(raw.stageStartedOn), episode: Number(raw.episode), sessionTotalSeconds: Number(raw.sessionTotalSeconds), status: raw.status as RunWalkProgramme["status"],
    ...(typeof raw.completedTrialMainSeconds === "number" ? { completedTrialMainSeconds: raw.completedTrialMainSeconds } : {}),
    ...(typeof raw.completedTrialTotalSeconds === "number" ? { completedTrialTotalSeconds: raw.completedTrialTotalSeconds } : {}),
    ...(typeof raw.completedTrialWeeklyMinutes === "number" ? { completedTrialWeeklyMinutes: raw.completedTrialWeeklyMinutes } : {}) };
}

/** Original issued identity/dose excludes metadata added by sync and database row IDs. */
export function runningDoseSignature(workout: Pick<PrescribedRunningEvidence, "modality" | "stimulus" | "durationSeconds" | "blocks">): string {
  const blocks = [...workout.blocks].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
  const value = { modality: workout.modality, stimulus: workout.stimulus, durationSeconds: workout.durationSeconds,
    blocks: blocks.map((block) => ({ blockType: block.blockType, stimulus: block.stimulus, durationSeconds: block.durationSeconds ?? null,
      steps: [...block.steps].sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)).map((step) => ({ kind: step.kind, durationSeconds: step.durationSeconds ?? null, target: step.target ?? null })) })) };
  return createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");
}
export function stampIssuedRunningDose(workout: PlannedWorkoutDraft, programme?: RunWalkProgramme): PlannedWorkoutDraft {
  if (workout.modality !== "run") return workout;
  const mainSeconds = workout.blocks.filter((block) => !["warmup", "cooldown"].includes(block.blockType)).flatMap((block) => block.steps)
    .filter((step) => !["warmup", "cooldown"].includes(step.kind)).reduce((sum, step) => sum + (step.durationSeconds ?? 0), 0);
  return { ...workout, prescription: { ...workout.prescription,
    issuedRunningDose: { policyVersion: RUN_WALK_POLICY, durationSeconds: workout.durationSeconds, mainSeconds, signature: runningDoseSignature(workout) },
    ...(programme ? { runWalkProgramme: { ...programme, continuousTrial: programme.status === "active" && programme.stageIndex === RUN_WALK_LADDER.length } } : {}) } };
}
export function adequateRunningEvidence(row: PrescribedRunningEvidence, readiness?: ReadinessForPlanning, now?: Date, allowReentry = false): boolean {
  const prescription = record(row.prescription);
  const issued = record(prescription?.issuedRunningDose);
  if (row.status !== "completed" || row.modality !== "run" || row.edits?.some((edit) => edit.operation !== "skip")
    || prescription?.workoutEditId || prescription?.source === "explicitWorkoutChange" || prescription?.sourceExposureEligible === false && !allowReentry
    || issued?.policyVersion !== RUN_WALK_POLICY || issued.signature !== runningDoseSignature(row) || issued.durationSeconds !== row.durationSeconds) return false;
  return row.completions.some((completion) => completion.performedAsIssued !== false
    && (!completion.prescriptionRevision || completion.performedAsIssued === true && (allowReentry
      ? completion.prescriptionRevision.programmeExposureEligible : completion.prescriptionRevision.sourceExposureEligible))
    && ["completed", "feltEasy"].includes(completion.completionQuality)
    && (!now || completion.completedAt <= now)
    && completion.durationSeconds != null && completion.durationSeconds >= row.durationSeconds * .8
    && !unexpectedRunningEffort({ ...completion, stimulus: completion.prescriptionRevision?.stimulus ?? row.stimulus }, readiness));
}
export function freshReadiness(rows: ReadinessForPlanning[], now: Date): ReadinessForPlanning | undefined {
  return [...rows].filter((row) => row.date >= new Date(day(now).getTime() - 86400000) && row.date <= now).sort((a, b) => b.date.getTime() - a.date.getTime())[0];
}
export function sameRunWalkProgramme(first: unknown, second: unknown): boolean { return JSON.stringify(canonical(first ?? null)) === JSON.stringify(canonical(second ?? null)); }
function record(value: unknown): Record<string, unknown> | undefined { return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined; }
function canonical(value: any): any { return Array.isArray(value) ? value.map(canonical) : value != null && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])])) : value; }
function day(value: Date): Date { return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate())); }
function dayKey(value: Date): string { return day(value).toISOString().slice(0, 10); }
