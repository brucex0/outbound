import { Prisma } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import { activityFact, identityColumns, type Fact, STATISTICS_VERSION } from "./facts.js";
import { statisticsSnapshot, totals } from "./engine.js";
import { StatisticsCalendar } from "./calendar.js";
// Bounded process cache. Revision checks happen against the database on every request.
const cache = new Map<string, { expires: number; revision: number; goalRevision: string; value: unknown }>();
export async function accountStatistics(userId: string, timeZone: string, firstWeekday: number) {
  const db = getPrismaClient(), now = new Date(), calendar = new StatisticsCalendar(timeZone, firstWeekday);
  const user = await db.user.findUniqueOrThrow({ where: { id: userId }, select: { statisticsRevision: true } });
  const goal = await db.trainingGoal.findFirst({
    where: { userId, status: "active" }, orderBy: { createdAt: "desc" },
    select: { id: true, updatedAt: true },
  });
  const goalRevision = goal ? `${goal.id}:${goal.updatedAt.toISOString()}` : "none";
  const key = `${userId}:${timeZone}:${firstWeekday}`;
  const cached = cache.get(key);
  if (cached && cached.revision === user.statisticsRevision && cached.goalRevision === goalRevision && cached.expires > +now) return cached.value;
  const result = await db.$transaction(async tx => {
    const revision = (await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { statisticsRevision: true } })).statisticsRevision;
    const rows = await tx.activity.findMany({ where: { userId, deletedAt: null }, select: { id: true, updatedAt: true, statisticsFacts: true }, orderBy: { startedAt: "desc" } });
    const facts: Fact[] = [];
    for (const row of rows) {
      let fact = row.statisticsFacts as Fact | null;
      if (fact?.version !== STATISTICS_VERSION) {
        const full = await tx.activity.findUniqueOrThrow({ where: { id: row.id } });
        fact = activityFact(full);
        await tx.activity.update({ where: { id: row.id }, data: { statisticsFacts: fact as unknown as Prisma.InputJsonValue, ...identityColumns(fact), updatedAt: row.updatedAt } });
      }
      facts.push(fact);
    }
    const weekStart = calendar.start(now, "week"), weekEnd = calendar.add(weekStart, 1, "week");
    const currentWeek = facts.filter(a => Date.parse(a.startedAt) >= +weekStart && Date.parse(a.startedAt) <= +weekEnd);
    // Personal frequency is independent of prescribed-workout completion and Progress eligibility.
    const runningGoal = await tx.trainingGoal.findFirst({
      where: { userId, status: "active" }, orderBy: { createdAt: "desc" },
      select: { activities: true, daysPerWeekTarget: true, preferredDays: true },
    });
    const weeklyRunGoal = weeklyRunningProgress(facts, runningGoal, now, calendar);
    const gear: Record<string, { distanceMeters: number; lastUsedAt: string | null }> = {};
    for (const fact of facts) if (fact.gearID) {
      const key = fact.gearID.toLowerCase(), item = gear[key] ?? { distanceMeters: 0, lastUsedAt: null };
      item.distanceMeters += Math.max(0, fact.distanceMeters);
      if (!item.lastUsedAt || fact.startedAt > item.lastUsedAt) item.lastUsedAt = fact.startedAt;
      gear[key] = item;
    }
    const paces = facts.filter(a => a.activityType === "running" && a.durationSeconds >= 300 && a.distanceMeters >= 500 && Date.parse(a.startedAt) >= +now - 30 * 86_400_000 && Date.parse(a.startedAt) <= +now)
      .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt)).map(a => ({ date: a.startedAt, pace: a.averagePace ?? a.durationSeconds * 1_000 / a.distanceMeters }))
      .filter(a => Number.isFinite(a.pace) && a.pace >= 60 && a.pace <= 3_600).slice(0, 10).map(a => a.pace).sort((a, b) => a - b);
    const coachingReferencePace = paces.length ? (paces[Math.floor((paces.length - 1) / 2)] + paces[Math.floor(paces.length / 2)]) / 2 : null;
    const sports = Object.fromEntries([...new Set(facts.map(a => a.activityType))].sort().map(sport => [sport, statisticsSnapshot(facts.filter(a => a.activityType === sport), now, calendar)]));
    return { coachingReferencePace, algorithmVersion: STATISTICS_VERSION, revision, computedAt: now.toISOString(), timeZone, firstWeekday, status: "complete", all: statisticsSnapshot(facts, now, calendar), sports, lifetime: totals(facts), currentWeek: totals(currentWeek), weekStart: weekStart.toISOString(), weekEnd: weekEnd.toISOString(), gear, weeklyRunGoal, outboundActivityCount: facts.filter(a => a.sourceKind === "outbound").length };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 120_000 });
  if (cache.size >= 256) cache.delete(cache.keys().next().value!);
  cache.set(key, { revision: result.revision, goalRevision, expires: Math.min(+now + 60_000, +calendar.add(calendar.start(now, "day"), 1, "day")), value: result });
  return result;
}

/** Use the recording save threshold for every source, independently of plan completion. */
export function weeklyRunningProgress(
  facts: Pick<Fact, "activityType" | "startedAt" | "durationSeconds" | "distanceMeters">[],
  goal: { activities: string[]; daysPerWeekTarget: number; preferredDays: string[] } | null,
  now: Date,
  calendar: StatisticsCalendar,
) {
  const weekStart = calendar.start(now, "week");
  const weekEnd = calendar.add(weekStart, 1, "week");
  const completedRuns = facts.filter(a => a.activityType === "running" && (a.durationSeconds >= 300 || a.distanceMeters >= 500)
    && Date.parse(a.startedAt) >= +weekStart && Date.parse(a.startedAt) < +weekEnd
    && Date.parse(a.startedAt) <= +now).length;
  // A mixed-sport sessions/week choice is not a runs/week goal.
  const targetRuns = goal?.activities.length === 1 && goal.activities[0] === "run"
    && goal.daysPerWeekTarget > 0 ? goal.daysPerWeekTarget : null;
  const weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
  const preferredDays = new Set(goal?.preferredDays.map(day => day.trim().toLowerCase().slice(0, 3)));
  const hasCompleteSchedule = targetRuns !== null && preferredDays.size === targetRuns
    && [...preferredDays].every(day => weekdays.includes(day));
  let scheduledRunsByToday: number | null = null;
  if (hasCompleteSchedule) {
    scheduledRunsByToday = 0;
    const today = calendar.start(now, "day");
    for (let date = weekStart; +date <= +today; date = calendar.add(date, 1, "day")) {
      if (preferredDays.has(weekdays[calendar.local(date).getUTCDay()])) scheduledRunsByToday++;
    }
  }
  return { completedRuns, targetRuns, scheduledRunsByToday };
}
