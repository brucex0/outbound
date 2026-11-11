import type { Prisma } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import { StatisticsCalendar } from "./statistics/calendar.js";

export const CALENDAR_POLICY_VERSION = "monday-v1" as const;
export const ACCOUNT_FIRST_WEEKDAY = 2 as const; // Foundation: Monday
export interface PlanningCalendarContext {
  policyVersion: typeof CALENDAR_POLICY_VERSION;
  timeZone: string;
  firstWeekday: typeof ACCOUNT_FIRST_WEEKDAY;
  weekStart: string; // Inclusive instant in account time zone.
  weekEnd: string; // Exclusive instant in account time zone.
  planStartDate: string | null; // Logical date label, not an instant.
  planWeekIndex: number | null;
  isPartialWeek: boolean;
}
export function validCalendarTimeZone(value: unknown): value is string {
  if (typeof value !== "string" || !value || value.length > 100) return false;
  try { new Intl.DateTimeFormat("en-US", { timeZone: value }); return true; } catch { return false; }
}
/** First valid device hint wins atomically. A server-only UTC fallback is never saved. */
export async function accountTimeZone(userId: string, hint?: string | null, db: Prisma.TransactionClient = getPrismaClient()): Promise<string> {
  if (validCalendarTimeZone(hint)) {
    const result = await db.user.updateMany({ where: { id: userId, calendarTimeZone: null }, data: { calendarTimeZone: hint } });
    if (result.count) console.info("[calendar] policy_initialized", { policy: CALENDAR_POLICY_VERSION, source: "device" });
  }
  const user = await db.user.findUniqueOrThrow({ where: { id: userId }, select: { calendarTimeZone: true } });
  return validCalendarTimeZone(user.calendarTimeZone) ? user.calendarTimeZone : "UTC";
}
/** Schedule storage encodes a local date label at UTC midnight; never shift stored rows. */
export function accountDateLabel(instant: Date, timeZone: string): Date {
  const local = new StatisticsCalendar(timeZone, ACCOUNT_FIRST_WEEKDAY).local(instant);
  return new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
}
export function mondayDateLabel(label: Date): Date {
  return new Date(Date.UTC(label.getUTCFullYear(), label.getUTCMonth(), label.getUTCDate() - (label.getUTCDay() + 6) % 7));
}
export function planningCalendarContext(timeZone: string, now: Date, planCreatedAt?: Date | null): PlanningCalendarContext {
  const calendar = new StatisticsCalendar(timeZone, ACCOUNT_FIRST_WEEKDAY);
  const weekStart = calendar.start(now, "week");
  const planStart = planCreatedAt ? accountDateLabel(planCreatedAt, timeZone) : null;
  const index = planStart ? Math.max(1, Math.round((mondayDateLabel(accountDateLabel(now, timeZone)).getTime() - mondayDateLabel(planStart).getTime()) / 604800000) + 1) : null;
  return { policyVersion: CALENDAR_POLICY_VERSION, timeZone, firstWeekday: ACCOUNT_FIRST_WEEKDAY,
    weekStart: weekStart.toISOString(), weekEnd: calendar.add(weekStart, 1, "week").toISOString(),
    planStartDate: planStart?.toISOString().slice(0, 10) ?? null, planWeekIndex: index,
    isPartialWeek: index === 1 && planStart?.getUTCDay() !== 1 };
}
