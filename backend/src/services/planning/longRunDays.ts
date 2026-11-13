import type { GeneratePlanInput } from "./generator.js";
import type { Modality } from "./types.js";

const weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
export type LongRunDaysCategory = "selection" | "capacity" | "modalities" | "programme" | "catalog";
export type LongRunDaysCode = `long_run_days_${LongRunDaysCategory}`;
export class LongRunDaysError extends Error {
  readonly code: LongRunDaysCode;
  constructor(readonly category: LongRunDaysCategory) {
    const messages = {
      selection: "Choose long-run days from your selected training days, leaving at least one ordinary run.",
      capacity: "Your current running history and weekly time cannot support every selected long run. Select fewer long-run days or a different schedule.",
      modalities: "These long-run days leave no room for an ordinary run and each selected activity. Select fewer long-run days or more weekly sessions.",
      programme: "Long-run days are not available during a starting-out or return-to-running programme. Remove them to continue with the programme.",
      catalog: "Custom long-run days are available for personalized plans. Choose a personalized plan or remove the long-run days.",
    };
    super(messages[category]);
    this.code = `long_run_days_${category}`;
  }
}

export function preferredLongRunDays(constraints?: Record<string, unknown>): string[] {
  const value = constraints?.preferredLongRunDays;
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 6 || value.some((day) => typeof day !== "string" || !weekdays.includes(day))) {
    throw new LongRunDaysError("selection");
  }
  return [...new Set(value)] as string[];
}

/** Explicit long slots consume existing sessions; never drop another selected sport. */
export function longRunWeekModalities(goal: GeneratePlanInput["goal"], dates: Date[], longDays: string[]): Map<number, Modality> | undefined {
  if (!longDays.length) return undefined;
  if (!goal.activities.includes("run") || longDays.some((day) => !goal.preferredDays.includes(day))
      || goal.preferredDays.length > goal.daysPerWeekTarget || dates.length !== goal.daysPerWeekTarget) {
    throw new LongRunDaysError("selection");
  }
  const quotas = new Map(goal.activities.map((activity) => [activity, activity === "run" ? longDays.length + 1 : 1]));
  let allocated = [...quotas.values()].reduce((sum, count) => sum + count, 0);
  if (allocated > dates.length) throw new LongRunDaysError(goal.activities.length > 1 ? "modalities" : "selection");
  while (allocated < dates.length) {
    const activity = [...goal.activities].sort((a, b) => quotas.get(a)! - quotas.get(b)!)[0]!;
    quotas.set(activity, quotas.get(activity)! + 1);
    allocated++;
  }
  const result = new Map<number, Modality>();
  for (const date of dates) {
    if (longDays.includes(weekdays[date.getUTCDay()]!)) {
      result.set(date.getUTCDay(), "run");
      quotas.set("run", quotas.get("run")! - 1);
    }
  }
  for (let index = 0; index < dates.length; index++) {
    const date = dates[index]!;
    if (result.has(date.getUTCDay())) continue;
    const activity = goal.activities.map((_, offset) => goal.activities[(index + offset) % goal.activities.length]!)
      .find((candidate) => quotas.get(candidate)! > 0)!;
    result.set(date.getUTCDay(), activity);
    quotas.set(activity, quotas.get(activity)! - 1);
  }
  return result;
}

/** Existing meaningful-long criteria, with one shared evidenced weekly budget. */
export function longRunAllocation(input: {
  sessions: number; longSessions: number; weeklySeconds: number;
  ordinaryCeiling: number; longCeiling: number; minimum: number;
  ordinaryFloor?: number;
}): { ordinarySeconds: number; longSeconds: number } {
  const { sessions, longSessions, weeklySeconds, ordinaryCeiling, longCeiling, minimum } = input;
  // Explicit preferences cannot manufacture a long dose from equal-session or
  // sparse evidence by shortening ordinary runs. Preserve the existing guard.
  if (longCeiling < ordinaryCeiling * 1.15 || longCeiling - ordinaryCeiling < 300) throw new LongRunDaysError("capacity");
  const ordinaryCount = sessions - longSessions;
  if (ordinaryCount < 1) throw new LongRunDaysError("selection");
  const target = Math.min(weeklySeconds, ordinaryCeiling * ordinaryCount + longCeiling * longSessions);
  const ordinarySeconds = Math.max(input.ordinaryFloor ?? 0, Math.floor(Math.min(ordinaryCeiling, longCeiling / 1.15, longCeiling - 300,
    (target - longSessions * 300) / sessions, target / (ordinaryCount + 1.15 * longSessions))));
  const longSeconds = Math.floor(Math.min(longCeiling, (target - ordinarySeconds * ordinaryCount) / longSessions));
  if (ordinarySeconds < minimum || longSeconds < ordinarySeconds * 1.15 || longSeconds - ordinarySeconds < 300) {
    throw new LongRunDaysError("capacity");
  }
  return { ordinarySeconds, longSeconds };
}
