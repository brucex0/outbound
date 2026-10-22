import { Prisma } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import { activityFact, identityColumns, type Fact, STATISTICS_VERSION } from "./facts.js";
import { statisticsSnapshot, totals } from "./engine.js";
import { StatisticsCalendar } from "./calendar.js";
// Bounded process cache. Revision checks happen against the database on every request.
const cache = new Map<string, { expires: number; revision: number; value: unknown }>();
export async function accountStatistics(userId: string, timeZone: string, firstWeekday: number) {
  const db = getPrismaClient(), now = new Date(), calendar = new StatisticsCalendar(timeZone, firstWeekday);
  const user = await db.user.findUniqueOrThrow({ where: { id: userId }, select: { statisticsRevision: true } });
  const key = `${userId}:${timeZone}:${firstWeekday}`;
  const cached = cache.get(key);
  if (cached && cached.revision === user.statisticsRevision && cached.expires > +now) return cached.value;
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
    return { coachingReferencePace, algorithmVersion: STATISTICS_VERSION, revision, computedAt: now.toISOString(), timeZone, firstWeekday, status: "complete", all: statisticsSnapshot(facts, now, calendar), sports, lifetime: totals(facts), currentWeek: totals(currentWeek), weekStart: weekStart.toISOString(), weekEnd: weekEnd.toISOString(), gear, outboundActivityCount: facts.filter(a => a.sourceKind === "outbound").length };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 120_000 });
  if (cache.size >= 256) cache.delete(cache.keys().next().value!);
  cache.set(key, { revision: result.revision, expires: Math.min(+now + 60_000, +calendar.add(calendar.start(now, "day"), 1, "day")), value: result });
  return result;
}
