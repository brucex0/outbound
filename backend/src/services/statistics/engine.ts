import { StatisticsCalendar } from "./calendar.js";
import { type Fact, targets } from "./facts.js";
export const totals = (items: Fact[]) => ({ activityCount: items.length, distanceMeters: items.reduce((n, a) => n + Math.max(0, a.distanceMeters), 0), durationSeconds: items.reduce((n, a) => n + Math.max(0, a.durationSeconds), 0), elevationMeters: items.reduce((n, a) => n + Math.max(0, a.elevationGainMeters ?? 0), 0) });
const round = (x: number) => Math.sign(x) * Math.round(Math.abs(x)); // Swift's ties-away-from-zero.
const between = (items: Fact[], start: Date, end: Date) => items.filter(a => Date.parse(a.startedAt) >= +start && Date.parse(a.startedAt) <= +end);
const sum = (items: Fact[], fn: (a: Fact) => number) => items.reduce((n, a) => n + fn(a), 0);
const recordTitles = ["400m", "1K", "1 mile", "5K", "10K", "10 mile", "Half marathon", "Marathon"];
type Effort = { kind: string; activityID: string | null; activityTitle: string | null; date: string; durationSeconds: number | null; distanceMeters: number | null; elevationMeters: number | null; source: string };
function effort(a: Fact, kind: string, seconds = a.durationSeconds, distance = a.distanceMeters, source = "activitySummary"): Effort {
  return { kind, activityID: a.id, activityTitle: a.title, date: a.startedAt, durationSeconds: seconds, distanceMeters: distance, elevationMeters: source === "activitySummary" ? a.elevationGainMeters : null, source };
}
function fastest(items: Fact[], target: number, kind: string, tolerance?: number): Effort | undefined {
  const windows = items.filter(a => a.windows[String(target)] != null).map(a => effort(a, kind, a.windows[String(target)], target, "routeWindow"));
  const candidates = windows.length ? windows : items.filter(a => a.distanceMeters >= target && a.durationSeconds > 0 && (tolerance == null || a.distanceMeters - target <= tolerance)).map(a => effort(a, kind, a.durationSeconds, a.distanceMeters, "wholeActivityFallback"));
  return candidates.sort((a, b) => a.durationSeconds! - b.durationSeconds! || Date.parse(b.date) - Date.parse(a.date))[0];
}
export function statisticsSnapshot(facts: Fact[], now: Date, calendar: StatisticsCalendar) {
  const eligible = facts.filter(a => a.durationSeconds > 60).sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt));
  const end = new Date(+now + 1_000), weekStart = calendar.start(now, "week");
  const week = between(eligible, weekStart, calendar.add(weekStart, 1, "week"));
  const bucket = (items: Fact[], start: Date, finish: Date) => ({ startDate: start.toISOString(), endDate: finish.toISOString(), totals: totals(between(items, start, finish)) });
  const buckets = (items: Fact[], count: number, unit: "week" | "month") => Array.from({ length: count }, (_, i) => {
    const start = calendar.add(calendar.start(now, unit), i - count + 1, unit);
    return bucket(items, start, calendar.add(start, 1, unit));
  });
  const weeks = (items: Fact[]) => buckets(items, 4, "week").map(b => ({ id: b.startDate, startDate: b.startDate, endDate: b.endDate, ...b.totals }));
  const comparisons = (["week", "month"] as const).map(kind => {
    const start = calendar.start(now, kind), previousStart = calendar.add(start, -1, kind);
    const currentEnd = new Date(Math.min(+end, +calendar.add(start, 1, kind)));
    const previousEnd = new Date(Math.min(+start, +previousStart + (+currentEnd - +start)));
    return { kind: kind as string, currentStart: start.toISOString(), currentEnd: currentEnd.toISOString(), previousStart: previousStart.toISOString(), previousEnd: previousEnd.toISOString(), current: totals(between(eligible, start, currentEnd)), previous: totals(between(eligible, previousStart, previousEnd)) };
  });
  const rollingStart = calendar.add(end, -28, "day"), priorStart = calendar.add(rollingStart, -28, "day");
  comparisons.push({ kind: "rolling28Days", currentStart: rollingStart.toISOString(), currentEnd: end.toISOString(), previousStart: priorStart.toISOString(), previousEnd: rollingStart.toISOString(), current: totals(between(eligible, rollingStart, end)), previous: totals(between(eligible, priorStart, rollingStart)) });
  const loadFor = (a: Fact) => Object.entries(a.heartRateZoneSeconds).reduce((n, [z, secs]) => n + Math.max(0, secs) / 60 * Math.min(5, Math.max(1, +z)), 0);
  const loadStart = calendar.add(end, -7, "day"), loadPrior = calendar.add(loadStart, -7, "day");
  const currentLoad = sum(between(eligible, loadStart, end), loadFor), previousLoad = sum(between(eligible, loadPrior, loadStart), loadFor);
  const hrItems = between(eligible.filter(a => Object.keys(a.heartRateZoneSeconds).length), rollingStart, end);
  const totalZoneSeconds = sum(hrItems, a => Object.values(a.heartRateZoneSeconds).reduce((n, x) => n + x, 0));
  const highZoneSeconds = sum(hrItems, a => Object.entries(a.heartRateZoneSeconds).reduce((n, [z, x]) => n + (+z >= 4 ? x : 0), 0));
  const trainingLoad = { currentSevenDays: currentLoad, previousSevenDays: previousLoad, rampPercent: previousLoad > 0 ? (currentLoad - previousLoad) / previousLoad * 100 : null, highIntensityPercent: totalZoneSeconds > 0 ? highZoneSeconds / totalZoneSeconds * 100 : null, heartRateActivityCount: hrItems.length };
  const insights: { priority: number; id: string; category: string; confidence: string; symbolName: string; evidence: Record<string, unknown> }[] = [];
  const add = (priority: number, id: string, category: string, confidence: string, symbolName: string, evidence: Record<string, unknown>) => insights.push({ priority, id, category, confidence, symbolName, evidence });
  const rolling = comparisons[2];
  const change = rolling.previous.distanceMeters > 0 ? (rolling.current.distanceMeters - rolling.previous.distanceMeters) / rolling.previous.distanceMeters * 100 : 0;
  if (rolling.current.activityCount >= 2 && rolling.previous.distanceMeters > 0 && Math.abs(change) >= 8) add(90, "rolling-distance", "volume", Math.min(rolling.current.activityCount, rolling.previous.activityCount) >= 5 ? "strong" : "solid", change >= 0 ? "chart.line.uptrend.xyaxis" : "arrow.down.right", { rollingDistance: { percent: round(change), currentMeters: rolling.current.distanceMeters, previousMeters: rolling.previous.distanceMeters } });
  const activeWeeks = Array.from({ length: 8 }, (_, i) => { const start = calendar.add(weekStart, -i, "week"); return between(eligible, start, calendar.add(start, 1, "week")).length > 0; }).filter(Boolean).length;
  if (activeWeeks >= 3) add(activeWeeks >= 6 ? 88 : 72, "active-weeks", "consistency", activeWeeks >= 6 ? "strong" : "solid", "calendar.badge.checkmark", { activeWeeks: { count: activeWeeks, total: 8 } });
  const weekMeters = totals(week).distanceMeters;
  const longestWeek = [...week].sort((a, b) => b.distanceMeters - a.distanceMeters)[0];
  if (week.length >= 2 && weekMeters > 0 && longestWeek) {
    const share = longestWeek.distanceMeters / weekMeters * 100;
    if (share >= 25) add(share > 50 ? 92 : 68, "long-run-share", "endurance", week.length >= 3 ? "solid" : "emerging", "arrow.left.and.right", { longRunShare: { percent: round(share), longRunMeters: longestWeek.distanceMeters, weekMeters } });
  }
  const comparable = eligible.filter(a => a.activityType === "running" && a.averageHeartRate != null && a.distanceMeters >= 1_000 && a.durationSeconds >= 600);
  const currentHR = between(comparable, rollingStart, end), previousHR = between(comparable, priorStart, rollingStart);
  if (currentHR.length >= 2 && previousHR.length >= 2) {
    const summary = (items: Fact[]) => { const t = totals(items); return { pace: t.durationSeconds / (t.distanceMeters / 1_000), hr: sum(items, a => a.averageHeartRate! * a.durationSeconds) / t.durationSeconds }; };
    const current = summary(currentHR), previous = summary(previousHR);
    const difference = round(current.hr - previous.hr), pacePercent = round((previous.pace - current.pace) / previous.pace * 100);
    if (Math.abs(difference) <= 5 && Math.abs(pacePercent) >= 2) add(86, "heart-rate-efficiency", "efficiency", currentHR.length + previousHR.length >= 8 ? "strong" : "solid", pacePercent >= 0 ? "heart.text.square.fill" : "waveform.path.ecg", { heartRateEfficiency: { pacePercent, heartRateDifference: difference } });
  }
  const ramp = trainingLoad.rampPercent;
  if (hrItems.length >= 4 && currentLoad > 0 && previousLoad > 0 && ramp != null && Math.abs(ramp) >= 20) add(Math.abs(ramp) >= 40 ? 96 : 82, "training-load", "trainingLoad", hrItems.length >= 7 ? "strong" : "solid", ramp > 0 ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent", { loadRamp: { percent: round(ramp), current: currentLoad, previous: previousLoad } });
  const high = trainingLoad.highIntensityPercent;
  if (hrItems.length >= 3 && high != null) add(high > 30 ? 94 : 64, "intensity-balance", "trainingBalance", hrItems.length >= 6 ? "strong" : "solid", "chart.bar.fill", { intensityBalance: { highIntensityPercent: round(high) } });
  const goals = eligible.filter(a => calendar.daysSince(new Date(a.startedAt), now) <= 28 && a.goalCompleted != null);
  if (goals.length >= 3) add(74, "goal-completion", "goals", goals.length >= 6 ? "strong" : "solid", "target", { goalCompletion: { completed: goals.filter(a => a.goalCompleted).length, total: goals.length } });
  const pattern = eligible.filter(a => calendar.daysSince(new Date(a.startedAt), now) <= 42);
  if (pattern.length >= 5) {
    const parts = { morning: 0, afternoon: 0, evening: 0 };
    for (const a of pattern) { const hour = calendar.local(new Date(a.startedAt)).getUTCHours(); parts[hour >= 5 && hour < 12 ? "morning" : hour >= 12 && hour < 18 ? "afternoon" : "evening"]++; }
    const dominant = Object.entries(parts).sort((a, b) => b[1] - a[1])[0], percent = round(dominant[1] / pattern.length * 100);
    if (percent >= 60) add(56, "preferred-time", "pattern", pattern.length >= 10 ? "strong" : "solid", dominant[0] === "morning" ? "sunrise.fill" : "clock.fill", { preferredTime: { dayPart: dominant[0], percent, total: pattern.length } });
  }
  const running = eligible.filter(a => a.activityType === "running"), runningWeeks = weeks(running);
  const bestEfforts = [fastest(running, 1_000, "fastestKilometer"), fastest(running, 1_609.344, "fastestMile"), fastest(running, 5_000, "fastestFiveKilometer")].filter((x): x is Effort => x != null);
  const longest = [...running].sort((a, b) => b.distanceMeters - a.distanceMeters)[0];
  if (longest) bestEfforts.push(effort(longest, "longestRun"));
  const hilliest = [...running].sort((a, b) => (b.elevationGainMeters ?? 0) - (a.elevationGainMeters ?? 0))[0];
  if (hilliest && (hilliest.elevationGainMeters ?? 0) > 0) bestEfforts.push(effort(hilliest, "mostElevation"));
  const bestWeek = [...runningWeeks].sort((a, b) => b.distanceMeters - a.distanceMeters)[0];
  if (bestWeek?.distanceMeters > 0) bestEfforts.push({ kind: "bestWeeklyDistance", activityID: null, activityTitle: null, date: bestWeek.startDate, durationSeconds: bestWeek.durationSeconds, distanceMeters: bestWeek.distanceMeters, elevationMeters: bestWeek.elevationMeters, source: "weeklyTotal" });
  const personalRecords = targets.flatMap((target, i) => { const record = fastest(running, target, "fastestKilometer", Math.max(5, Math.min(100, target * .01))); return record ? [{ title: recordTitles[i], targetMeters: target, effort: record }] : []; });
  const reference = personalRecords.filter(r => r.targetMeters >= 1_000 && r.targetMeters <= 21_097.5).sort((a, b) => b.targetMeters * (calendar.daysSince(new Date(b.effort.date), now) <= 90 ? 1 : .75) - a.targetMeters * (calendar.daysSince(new Date(a.effort.date), now) <= 90 ? 1 : .75))[0];
  const recentRuns = running.filter(a => calendar.daysSince(new Date(a.startedAt), now) <= 42).length;
  const confidence = running.length >= 12 && recentRuns >= 6 ? "high" : running.length >= 5 && recentRuns >= 3 ? "medium" : "low";
  const racePredictions = reference ? [["5K", 5_000], ["10K", 10_000], ["Half", 21_097.5], ["Marathon", 42_195]].map(([title, meters]) => ({ title, targetMeters: meters, predictedSeconds: round(reference.effort.durationSeconds! * Math.pow(Number(meters) / reference.targetMeters, 1.06)), confidence })) : [];
  const latest = eligible[0];
  const momentum = !latest ? null : calendar.daysSince(new Date(latest.startedAt), now) === 0 ? ["showedUpToday", "checkmark.circle.fill"] : calendar.daysSince(new Date(latest.startedAt), now) >= 2 ? ["backAfterRest", "arrow.clockwise"] : week.length >= 3 ? ["buildingRhythm", "waveform.path.ecg"] : latest.durationSeconds <= 900 ? ["shortCounts", "bolt.heart"] : week.length ? ["weekCount", "calendar"] : ["keepSimple", "sun.max"];
  return { currentWeek: totals(week), weeklyBuckets: weeks(eligible), comparisons, trendSeries: ([ ["fourWeeks",4,"week"], ["threeMonths",13,"week"], ["sixMonths",6,"month"], ["oneYear",12,"month"] ] as const).map(([range, count, unit]) => ({ range, buckets: buckets(eligible, count, unit) })), trainingLoad, insights: insights.sort((a, b) => b.priority - a.priority || a.id.localeCompare(b.id)).map(({ priority, ...insight }) => insight), bestEfforts, personalRecords, racePredictions, momentumNote: momentum ? { kind: momentum[0], symbolName: momentum[1], activityCount: week.length } : null, eligibleActivityCount: eligible.length };
}
