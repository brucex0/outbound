import { z } from "zod";
import { synchronizeRunningPrescription } from "./runningPrescription.js";
import type { PlannedWorkoutDraft } from "./types.js";

export const RUNNING_BENCHMARK_POLICY = "reported-maximal-running-v1";
export const runningBenchmarkSchema = z.object({
  activity: z.literal("run"),
  source: z.enum(["race", "timeTrial"]),
  maximalEffort: z.literal(true),
  distanceMeters: z.number().finite().min(1500).max(30000),
  durationSeconds: z.number().int().positive().max(86400),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use the date of the race or maximal time trial."),
}).strict();
export type RunningBenchmark = z.infer<typeof runningBenchmarkSchema>;
type Status = "absent" | "eligible" | "stale" | "future" | "invalid";
export interface BenchmarkResolution {
  status: Status;
  source: RunningBenchmark["source"] | null;
  report?: RunningBenchmark;
  performanceEstimate?: number;
  paceRanges?: Record<"easy" | "threshold" | "interval", { fasterSecondsPerKilometer: number; slowerSecondsPerKilometer: number }>;
}
export class RunningBenchmarkError extends Error {
  readonly code = "running_benchmark_invalid";
  constructor(readonly category: string) {
    super("Use a maximal running race or time trial from the last 12 weeks, with a valid date, distance (1.5 to 30 km) and finish time, or remove the benchmark to use effort guidance.");
  }
}
export class RunningBenchmarkConflictError extends Error {
  readonly code = "running_benchmark_goal_changed";
  constructor() { super("The active goal changed. Refresh the plan before editing the benchmark."); }
}

/** Published Daniels/Gilbert cost and performance equations; t minutes, v metres/minute.
 * This quotient is a performance estimate, never a measured laboratory VO2max.
 * Age/domain and oxygen-cost bands below are Plainstride product heuristics.
 */
export function resolveRunningBenchmark(value: unknown, now: Date): BenchmarkResolution {
  if (value == null) return { status: "absent", source: null };
  const parsed = runningBenchmarkSchema.safeParse(value);
  if (!parsed.success) return { status: "invalid", source: null };
  const benchmark = parsed.data;
  const date = new Date(`${benchmark.date}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== benchmark.date) return { status: "invalid", source: benchmark.source };
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const age = (today - date.getTime()) / 86400000;
  if (age < 0) return { status: "future", source: benchmark.source, report: benchmark };
  if (age > 84) return { status: "stale", source: benchmark.source, report: benchmark };
  const minutes = benchmark.durationSeconds / 60;
  const velocity = benchmark.distanceMeters / minutes;
  // Broad numerical domain guard, not a claim that every admitted result is accurate.
  if (velocity < 60 || velocity > 450) return { status: "invalid", source: benchmark.source };
  const cost = -4.6 + 0.182258 * velocity + 0.000104 * velocity ** 2;
  const fraction = 0.8 + 0.1894393 * Math.exp(-0.012778 * minutes) + 0.2989558 * Math.exp(-0.1932605 * minutes);
  const performanceEstimate = cost / fraction;
  if (!Number.isFinite(performanceEstimate) || performanceEstimate < 5 || performanceEstimate > 100) return { status: "invalid", source: benchmark.source };
  const range = (low: number, high: number) => {
    const pace = (fraction: number) => {
      const velocity = (-0.182258 + Math.sqrt(0.182258 ** 2 + 4 * 0.000104 * (4.6 + performanceEstimate * fraction))) / (2 * 0.000104);
      return 60000 / velocity;
    };
    return { fasterSecondsPerKilometer: Math.round(pace(high)), slowerSecondsPerKilometer: Math.round(pace(low)) };
  };
  const paceRanges = { easy: range(0.59, 0.74), threshold: range(0.83, 0.88), interval: range(0.95, 1.00) };
  if (Object.values(paceRanges).some((range) => range.fasterSecondsPerKilometer < 120 || range.slowerSecondsPerKilometer > 1500)) return { status: "invalid", source: benchmark.source };
  return { status: "eligible", source: benchmark.source, report: benchmark, performanceEstimate, paceRanges };
}

/** Single stored representation; freeform constraints cannot bypass request validation. */
export function benchmarkConstraints(input: { activities: string[]; constraints?: Record<string, unknown>; runningBenchmark?: unknown }, now: Date): Record<string, unknown> {
  const constraints = { ...input.constraints };
  const top = input.runningBenchmark;
  const nested = constraints.runningBenchmark;
  for (const value of [top, nested]) if (value != null) {
    const result = resolveRunningBenchmark(value, now);
    if (result.status !== "eligible") throw new RunningBenchmarkError(result.status);
    if (!input.activities.includes("run")) throw new RunningBenchmarkError("not_running");
  }
  const canonical = (value: unknown) => value == null ? null : runningBenchmarkSchema.parse(value);
  if (top !== undefined && nested !== undefined && JSON.stringify(canonical(top)) !== JSON.stringify(canonical(nested))) throw new RunningBenchmarkError("conflicting_input");
  const value = top === undefined ? nested : top;
  if (value == null) delete constraints.runningBenchmark;
  else constraints.runningBenchmark = runningBenchmarkSchema.parse(value);
  return constraints;
}

export function runningBenchmarkDecision(constraints: Record<string, unknown> | undefined, now: Date) {
  const result = resolveRunningBenchmark(constraints?.runningBenchmark, now);
  if (["invalid", "future"].includes(result.status)) console.info("[planning] running_benchmark_fallback", { operation: "resolve", category: result.status });
  return { policyVersion: RUNNING_BENCHMARK_POLICY, status: result.status, source: result.source };
}

/** Compare fields, never JSON key order (PostgreSQL JSONB canonicalizes objects). */
export function runningBenchmarkDecisionChanged(previous: unknown, constraints: Record<string, unknown> | undefined, now: Date): boolean {
  const current = runningBenchmarkDecision(constraints, now);
  const prior = previous != null && typeof previous === "object" ? previous as Record<string, unknown> : {};
  return prior.policyVersion !== current.policyVersion || prior.status !== current.status || prior.source !== current.source;
}

export function sameRunningBenchmark(first: unknown, second: unknown): boolean {
  if (first == null && second == null) return true;
  const a = runningBenchmarkSchema.safeParse(first);
  const b = runningBenchmarkSchema.safeParse(second);
  return a.success && b.success && JSON.stringify(a.data) === JSON.stringify(b.data);
}

/** Only identified main running phases get pace; walks, warm-up and recoveries keep effort.
 * Existing RPE/detail stays authoritative when terrain/conditions make pace unsuitable.
 */
export function applyRunningBenchmark(workout: PlannedWorkoutDraft, constraints: Record<string, unknown> | undefined, now: Date): PlannedWorkoutDraft {
  if (workout.modality !== "run") return workout;
  const result = resolveRunningBenchmark(constraints?.runningBenchmark, now);
  const runWalk = workout.prescription.runWalk === true || workout.prescription.workoutKind === "run_walk";
  const blocks = workout.blocks.map((block) => ({ ...block, steps: block.steps.map((step) => {
    const target = step.target ?? {};
    const ownPace = target.paceEstimatePolicy === RUNNING_BENCHMARK_POLICY;
    // Authored/source/user pace is independent of this optional derived estimate.
    if (target.pace && !ownPace) return step;
    const { pace: _oldPace, paceEstimatePolicy: _oldPolicy, ...effort } = target;
    const band = ["tempo", "threshold"].includes(step.kind) ? "threshold"
      : ["speed", "interval"].includes(step.kind) ? "interval"
        : ["run", "easy"].includes(step.kind) || step.kind === "steady" && ["easyAerobic", "longEndurance"].includes(block.stimulus ?? "") ? "easy" : null;
    const supportingBlock = ["warmup", "cooldown", "recovery"].includes(block.blockType);
    const range = !runWalk && !supportingBlock && band ? result.paceRanges?.[band] : undefined;
    if (!range) return { ...step, target: effort };
    const midpoint = Math.round((range.fasterSecondsPerKilometer + range.slowerSecondsPerKilometer) / 2);
    return { ...step, target: { ...effort, paceEstimatePolicy: RUNNING_BENCHMARK_POLICY, pace: { reference: "absolute", targetSecondsPerKilometer: midpoint,
      athleteReferenceOffsetSeconds: 0, fasterToleranceSeconds: midpoint - range.fasterSecondsPerKilometer,
      slowerToleranceSeconds: range.slowerSecondsPerKilometer - midpoint } } };
  }) }));
  return synchronizeRunningPrescription({ ...workout, blocks, prescription: { ...workout.prescription,
    runningFitness: { policyVersion: RUNNING_BENCHMARK_POLICY, status: result.status, source: result.source,
      estimateKind: "reported_maximal_performance",
      paceIsEstimate: blocks.some((block) => block.steps.some((step) => step.target?.paceEstimatePolicy === RUNNING_BENCHMARK_POLICY)) } } });
}
