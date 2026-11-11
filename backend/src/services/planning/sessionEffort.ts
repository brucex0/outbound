import { Prisma } from "@prisma/client";
import type { ActivityForPlanning, ReadinessForPlanning } from "./types.js";

export const SESSION_EFFORT_POLICY = "reported-session-load-v3";
/** Match the existing athlete-state running classification for supported variants. */
export function isRunningActivityType(type: string): boolean {
  const normalized = type.toLowerCase();
  return normalized.includes("run") || normalized.includes("jog");
}
export function reportedEffort(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 10 ? value : null;
}

/** Project only the private reported rating; never load the lossless client snapshot. */
export async function withSessionEffort(db: Prisma.TransactionClient, userId: string, activities: ActivityForPlanning[]): Promise<ActivityForPlanning[]> {
  if (!activities.length) return activities;
  const ids = activities.map((activity) => activity.id);
  const [ratings, completions] = await Promise.all([
    db.$queryRaw<Array<{ id: string; rating: unknown }>>(Prisma.sql`
      SELECT "id", "clientData" -> 'sessionEffortRating' AS rating
      FROM "Activity" WHERE "userId" = ${userId} AND "id" IN (${Prisma.join(ids)})`),
    db.workoutCompletion.findMany({ where: { userId, activityId: { in: ids }, perceivedEffort: { not: null } },
      orderBy: { completedAt: "desc" }, select: { activityId: true, perceivedEffort: true } }),
  ]);
  const direct = new Map(ratings.map((row) => [row.id, reportedEffort(row.rating)]));
  const linked = new Map<string, number>();
  for (const completion of completions) {
    const rating = reportedEffort(completion.perceivedEffort);
    if (completion.activityId && rating != null && !linked.has(completion.activityId)) linked.set(completion.activityId, rating);
  }
  // Linked completion enriches the same activity; it never adds another load row.
  // Unlinked completions are deliberately not treated as additional activities.
  return activities.map((activity) => ({ ...activity, sessionEffortRating: direct.get(activity.id) ?? linked.get(activity.id) ?? null,
    sessionEffortProvenance: direct.get(activity.id) != null ? "activity_report" : linked.has(activity.id) ? "linked_completion_report" : null }));
}

export interface ReportedSessionLoad {
  policy: string;
  provenance: "runner_reported";
  current: ReturnType<typeof period>;
  baseline: ReturnType<typeof period>;
  baselineWeeklyLoad: number | null;
  ratio: number | null;
  comparable: boolean;
  baselineObservedWeeks: number;
  baselineReportedWeeks: number;
  evidence: "comparable" | "insufficient_reports" | "incomparable_coverage" | "unknown_duration" | "insufficient_baseline_history";
}
export function runningSessionLoad(activities: ActivityForPlanning[], now: Date): ReportedSessionLoad {
  const runs = activities.filter((row) => isRunningActivityType(row.type) && row.startedAt <= now);
  const weekAgo = now.getTime() - 7 * 86_400_000, baselineStart = now.getTime() - 28 * 86_400_000;
  const current = period(runs.filter((row) => row.startedAt.getTime() >= weekAgo));
  const baselineRows = runs.filter((row) => row.startedAt.getTime() >= baselineStart && row.startedAt.getTime() < weekAgo);
  const baseline = period(baselineRows);
  // Prior windows are [now-14d, now-7d), [now-21d, now-14d), [now-28d, now-21d).
  // An exact lower boundary belongs to the newer window, not a fabricated older one.
  const windowIndex = (row: ActivityForPlanning) => Math.min(2, Math.ceil((weekAgo - row.startedAt.getTime()) / (7 * 86_400_000)) - 1);
  const usableBaseline = baselineRows.filter((row) => row.durationSecs != null && Number.isFinite(row.durationSecs) && row.durationSecs > 0);
  const baselineObservedWeeks = new Set(usableBaseline.map(windowIndex)).size;
  const baselineReportedWeeks = new Set(usableBaseline.filter((row) => reportedEffort(row.sessionEffortRating) != null).map(windowIndex)).size;
  const sufficient = current.ratedSessions >= 2 && baseline.ratedSessions >= 4 && baseline.ratedWeeks >= 2
    && current.durationCoverage >= .8 && baseline.durationCoverage >= .8;
  const coverageMatches = Math.abs(current.durationCoverage - baseline.durationCoverage) <= 1e-9;
  const knownDurations = current.unknownDurationSessions === 0 && baseline.unknownDurationSessions === 0;
  const temporalBaseline = baselineObservedWeeks === 3;
  const comparable = sufficient && coverageMatches && knownDurations && temporalBaseline && baselineReportedWeeks === 3 && (baseline.observedLoad ?? 0) > 0;
  const baselineWeeklyLoad = baseline.observedLoad == null || !temporalBaseline ? null : baseline.observedLoad / 3;
  return { policy: SESSION_EFFORT_POLICY, provenance: "runner_reported", current, baseline,
    baselineWeeklyLoad, baselineObservedWeeks, baselineReportedWeeks, ratio: comparable ? current.observedLoad! / baselineWeeklyLoad! : null,
    comparable, evidence: !knownDurations ? "unknown_duration" : !temporalBaseline ? "insufficient_baseline_history" : !sufficient ? "insufficient_reports" : !coverageMatches || baselineReportedWeeks !== 3 ? "incomparable_coverage" : "comparable" };
}
function period(rows: ActivityForPlanning[]) {
  const eligible = rows.filter((row) => row.durationSecs != null && Number.isFinite(row.durationSecs) && row.durationSecs > 0);
  const rated = eligible.filter((row) => reportedEffort(row.sessionEffortRating) != null);
  const duration = eligible.reduce((sum, row) => sum + row.durationSecs!, 0);
  const ratedDuration = rated.reduce((sum, row) => sum + row.durationSecs!, 0);
  return { sessions: rows.length, knownDurationSessions: eligible.length, unknownDurationSessions: rows.length - eligible.length,
    ratedSessions: rated.length, missingReports: rows.filter((row) => reportedEffort(row.sessionEffortRating) == null).length,
    ratedWeeks: new Set(rated.map((row) => { const date = new Date(row.startedAt); date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7); return date.toISOString().slice(0, 10); })).size,
    durationCoverage: duration > 0 ? ratedDuration / duration : 0,
    observedLoad: rated.length ? rated.reduce((sum, row) => sum + row.durationSecs! / 60 * row.sessionEffortRating!, 0) : null,
    sourceCounts: { activity: rated.filter((row) => row.sessionEffortProvenance !== "linked_completion_report").length,
      linkedCompletion: rated.filter((row) => row.sessionEffortProvenance === "linked_completion_report").length } };
}

/** Numeric intensity is separate from explicit categorical difficulty. */
export function unexpectedRunningEffort(input: { perceivedEffort: number | null; stimulus?: string; completionQuality?: string }, readiness?: ReadinessForPlanning): boolean {
  if (input.completionQuality === "tooHard") return true;
  const rating = reportedEffort(input.perceivedEffort);
  if (rating == null) return false;
  if (["easyAerobic", "recovery", "longEndurance"].includes(input.stimulus ?? "")) return rating >= 8;
  // Intended hard work at8 is not unexpected difficulty by itself.
  return rating >= 9 && Boolean(readiness?.illnessOrPain || (readiness?.energy ?? 5) <= 2 || (readiness?.soreness ?? 0) >= 4);
}
