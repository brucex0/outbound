import { randomUUID } from "node:crypto";
import { Prisma, type GroupActivitySeries, type ActivityEvent } from "@prisma/client";
import { z } from "zod";
import { lockedGroup, isRetryableGroupTransaction } from "./groupLock.js";
import { getPrismaClient } from "./prisma.js";

const dayMs = 86_400_000;
const horizonDays = 90;
const dateSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine((value) => Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value, "Choose a valid date.");
export const recurrenceSchema = z.object({
  timeZone: z.string().min(1).max(100).refine((value) => { try { new Intl.DateTimeFormat("en", { timeZone: value }); return true; } catch { return false; } }, "Choose a valid time zone."),
  intervalWeeks: z.number().int().min(1).max(4),
  weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7).transform((days) => [...new Set(days)].sort()),
  untilDate: dateSchema.nullable().optional(),
});
export const occurrenceScopeSchema = z.enum(["this", "following", "series"]);
export type Recurrence = z.infer<typeof recurrenceSchema>;
type Database = Prisma.TransactionClient;
export type EventInput = {
  title: string; activityType: string; startsAt: string; durationMinutes: number;
  locationName?: string | null; latitude?: number | null; longitude?: number | null;
  note?: string | null; participationMode: string;
};
export class SeriesError extends Error {
  constructor(public readonly status: 403 | 409 | 422, message: string) { super(message); }
}

async function seriesTransaction<T>(operation: (db: Database) => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await getPrismaClient().$transaction(operation, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 20_000 });
    } catch (error) {
      if (!isRetryableGroupTransaction(error)) throw error;
      console.info("[activitySeries] retrying concurrent change", { operation: "change activity series", attempt: attempt + 1 });
    }
  }
  throw new SeriesError(409, "The activity series changed. Try again.");
}

export function localParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(date);
  const part = (name: string) => parts.find((p) => p.type === name)!.value;
  return { date: `${part("year")}-${part("month")}-${part("day")}`, time: `${part("hour")}:${part("minute")}` };
}

// Resolve wall time using the zone's actual offsets on both sides of a DST
// transition. Repeated times choose the first occurrence; missing times move
// forward by the gap. No fixed-offset or 7 * 24 hour recurrence arithmetic.
export function occurrenceInstant(date: string, time: string, timeZone: string) {
  const nominal = Date.parse(`${date}T${time}:00Z`);
  const offsets = new Set<number>();
  for (const hours of [-36, -12, 0, 12, 36]) {
    const probe = new Date(nominal + hours * 3_600_000);
    const local = localParts(probe, timeZone);
    offsets.add(Date.parse(`${local.date}T${local.time}:00Z`) - probe.getTime());
  }
  const choices = [...offsets].map((offset) => {
    const instant = new Date(nominal - offset);
    const local = localParts(instant, timeZone);
    return { instant, local: Date.parse(`${local.date}T${local.time}:00Z`) };
  });
  const exact = choices.filter((choice) => choice.local === nominal).sort((a, b) => a.instant.getTime() - b.instant.getTime());
  if (exact.length) return exact[0].instant;
  const after = choices.filter((choice) => choice.local > nominal).sort((a, b) => a.local - b.local);
  if (!after.length) throw new SeriesError(422, "This local date and time is unavailable.");
  return after[0].instant;
}

function dateNumber(date: string) { return Math.floor(Date.parse(`${date}T00:00:00Z`) / dayMs); }
function dateAt(number: number) { return new Date(number * dayMs).toISOString().slice(0, 10); }
function isoWeekday(number: number) { return ((new Date(number * dayMs).getUTCDay() + 6) % 7) + 1; }
function scheduledDate(series: Pick<GroupActivitySeries, "startDate" | "untilDate" | "weekdays" | "intervalWeeks">, date: string) {
  const number = dateNumber(date), start = dateNumber(series.startDate);
  const anchorMonday = start - isoWeekday(start) + 1;
  return date >= series.startDate && (!series.untilDate || date <= series.untilDate) && series.weekdays.includes(isoWeekday(number)) && Math.floor((number - anchorMonday) / 7) % series.intervalWeeks === 0;
}

export function seriesDefinition(input: EventInput, recurrence: Recurrence) {
  const local = localParts(new Date(input.startsAt), recurrence.timeZone);
  if (!recurrence.weekdays.includes(isoWeekday(dateNumber(local.date)))) throw new SeriesError(422, "The first activity date must be one of the repeat weekdays.");
  if (recurrence.untilDate && recurrence.untilDate < local.date) throw new SeriesError(422, "The repeat end date cannot precede the first activity.");
  return {
    title: input.title, activityType: input.activityType, locationName: input.locationName || null,
    latitude: input.latitude ?? null, longitude: input.longitude ?? null, note: input.note || null,
    participationMode: input.participationMode, durationMinutes: input.durationMinutes,
    timeZone: recurrence.timeZone, startDate: local.date, localTime: local.time,
    intervalWeeks: recurrence.intervalWeeks, weekdays: recurrence.weekdays, untilDate: recurrence.untilDate ?? null,
  };
}

function eventData(series: GroupActivitySeries, date: string) {
  const startsAt = occurrenceInstant(date, series.localTime, series.timeZone);
  return {
    groupId: series.groupId, creatorId: series.creatorId, seriesId: series.id, seriesFamilyId: series.familyId, occurrenceDate: date,
    title: series.title, activityType: series.activityType, locationName: series.locationName,
    latitude: series.latitude, longitude: series.longitude, note: series.note,
    participationMode: series.participationMode, activityPolicy: "fixed", visibility: series.visibility,
    startsAt, endsAt: new Date(startsAt.getTime() + series.durationMinutes * 60_000),
  };
}

async function materialize(db: Database, series: GroupActivitySeries, now = new Date()) {
  if (series.stopped) return;
  const today = localParts(now, series.timeZone).date;
  const first = series.startDate > today ? series.startDate : today;
  const last = dateAt(dateNumber(first) + horizonDays);
  const existing = await db.activityEvent.findMany({ where: { seriesFamilyId: series.familyId, occurrenceDate: { gte: first, lte: last } }, select: { occurrenceDate: true } });
  const keys = new Set(existing.map((event) => event.occurrenceDate));
  const data: Prisma.ActivityEventCreateManyInput[] = [];
  for (let day = dateNumber(first); day <= dateNumber(last); day++) {
    const date = dateAt(day);
    if (keys.has(date) || !scheduledDate(series, date)) continue;
    const event = eventData(series, date);
    // Do not invent historical attendance or results after a long dormant period.
    if (event.endsAt <= now) continue;
    data.push({ id: randomUUID(), ...event, status: event.startsAt <= now ? "active" : "scheduled" });
  }
  if (!data.length) return;
  await db.activityEvent.createMany({ data, skipDuplicates: true });
  const inserted = await db.activityEvent.findMany({ where: { id: { in: data.map((event) => event.id!) } }, select: { id: true } });
  await db.activityEventParticipant.createMany({ data: inserted.map((event) => ({ activityEventId: event.id, userId: series.creatorId, status: "going" })), skipDuplicates: true });
}

export async function ensureGroupActivityOccurrences(viewerId: string, groupId?: string) {
  const db = getPrismaClient();
  const series = await db.groupActivitySeries.findMany({ where: { stopped: false, ...(groupId ? { groupId } : {}), group: { lifecycle: "active", scheduledActivitiesEnabled: true, members: { some: { userId: viewerId, status: "active" } } } }, select: { id: true, creatorId: true, groupId: true } });
  for (const item of series) {
    // A removed organizer cannot silently create more activities through a series.
    await db.$transaction(async (tx) => {
      const group = await lockedGroup(tx, item.groupId);
      if (group.lifecycle !== "active" || !group.scheduledActivitiesEnabled) return;
      const creator = await tx.groupMember.findUnique({ where: { groupId_userId: { groupId: item.groupId, userId: item.creatorId } }, select: { status: true } });
      if (creator?.status !== "active") return;
      const current = await tx.groupActivitySeries.findUniqueOrThrow({ where: { id: item.id } });
      await materialize(tx, current);
    });
  }
}

export async function createActivitySeries(creatorId: string, groupId: string, visibility: string, input: EventInput, recurrence: Recurrence, idempotencyKey: string) {
  const db = getPrismaClient();
  const key = `${creatorId}:${idempotencyKey}`;
  const existing = await db.groupActivitySeries.findUnique({ where: { creationKey: key }, include: { events: { orderBy: { startsAt: "asc" }, take: 1 } } });
  if (existing?.events[0]) return existing.events[0].id;
  try {
    return await seriesTransaction(async (tx) => {
    const { group, member } = await assertSeriesManager(tx, { groupId }, creatorId, true);
    if (!["owner", "admin"].includes(member.role) && !(group.trustPolicy === "trusted_private" && group.memberActivityCreation)) throw new SeriesError(403, "Group activity creation is not available to this member.");
    const retried = await tx.groupActivitySeries.findUnique({ where: { creationKey: key }, include: { events: { orderBy: { startsAt: "asc" }, take: 1 } } });
    if (retried?.events[0]) return retried.events[0].id;
    const series = await tx.groupActivitySeries.create({ data: { creatorId, groupId, visibility, creationKey: key, ...seriesDefinition(input, recurrence) } });
    // Preserve the exact selected first instant, including the later side of a
    // repeated DST hour. Subsequent occurrences follow the stored wall clock.
    const startsAt = new Date(input.startsAt);
    const first = await tx.activityEvent.create({ data: { ...eventData(series, series.startDate), startsAt, endsAt: new Date(startsAt.getTime() + input.durationMinutes * 60_000) } });
    await tx.activityEventParticipant.create({ data: { activityEventId: first.id, userId: creatorId, status: "going" } });
    await materialize(tx, series);
    return first.id;
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      // A concurrent retry can hold an older serializable snapshot while the
      // winning request commits the same key. Read its canonical result fresh.
      const winner = await db.groupActivitySeries.findUnique({ where: { creationKey: key }, include: { events: { orderBy: { startsAt: "asc" }, take: 1 } } });
      if (winner?.events[0]) return winner.events[0].id;
    }
    throw error;
  }
}

export async function cancelActivityEvents(db: Database, events: ActivityEvent[], actorId: string) {
  for (const event of events) {
    const changed = await db.activityEvent.updateMany({ where: { id: event.id, status: "scheduled", startsAt: { gt: new Date() } }, data: { status: "cancelled" } });
    if (!changed.count) continue;
    await db.liveGroupSession.updateMany({ where: { activityEventId: event.id, status: "active" }, data: { status: "ended", endedAt: new Date() } });
    const [participants, invitations] = await Promise.all([
      db.activityEventParticipant.findMany({ where: { activityEventId: event.id, status: { in: ["going", "participating"] } }, select: { userId: true } }),
      db.invitation.findMany({ where: { activityEventId: event.id, status: "pending" }, select: { id: true, recipientId: true } }),
    ]);
    await db.invitation.updateMany({ where: { activityEventId: event.id, status: "pending" }, data: { status: "cancelled", expiresAt: new Date() } });
    await db.socialNotification.deleteMany({ where: { type: "runInvitation", objectId: { in: invitations.map((invite) => invite.id) } } });
    const recipients = new Set([...participants.map((p) => p.userId), ...invitations.flatMap((invite) => invite.recipientId ? [invite.recipientId] : [])]);
    recipients.delete(actorId);
    await db.socialNotification.createMany({ data: [...recipients].map((recipientId) => ({ recipientId, actorId, type: "activityEventCancelled", objectId: event.id, message: "A planned activity was cancelled.", dedupeKey: `activityEventCancelled:${event.id}:${recipientId}` })), skipDuplicates: true });
  }
}

// Split future-rule edits into a new series segment. Matching occurrence dates
// retain their event IDs, RSVPs, invitations and personal recording links.
export async function updateActivitySeries(eventId: string, actorId: string, scope: "following" | "series", input: EventInput, recurrence: Recurrence | null) {
  return seriesTransaction(async (tx) => {
    const selected = await tx.activityEvent.findUnique({ where: { id: eventId } });
    if (!selected?.seriesId || selected.creatorId !== actorId || selected.status !== "scheduled" || selected.startsAt <= new Date()) throw new SeriesError(409, "Only future activities you created can be edited.");
    if (await tx.activityEventParticipant.findFirst({ where: { activityEventId: selected.id, startedAt: { not: null } }, select: { id: true } })) throw new SeriesError(409, "Activities with recorded participation cannot be edited.");
    const old = await tx.groupActivitySeries.findUniqueOrThrow({ where: { id: selected.seriesId } });
    await assertSeriesManager(tx, old, actorId, true);
    const family = await tx.groupActivitySeries.findMany({ where: { familyId: old.familyId }, orderBy: { startDate: "asc" } });
    const cutoff = scope === "following" ? selected.occurrenceDate! : family[0].startDate;
    const events = await tx.activityEvent.findMany({ where: { seriesFamilyId: old.familyId, occurrenceDate: { gte: cutoff }, startsAt: { gt: new Date() }, participants: { none: { startedAt: { not: null } } }, status: { in: ["scheduled", "cancelled"] } }, orderBy: { startsAt: "asc" } });
    for (const segment of family) {
      if (scope === "series" || segment.startDate >= cutoff) await tx.groupActivitySeries.update({ where: { id: segment.id }, data: { stopped: true } });
      else if (!segment.untilDate || segment.untilDate >= cutoff) await tx.groupActivitySeries.update({ where: { id: segment.id }, data: { untilDate: dateAt(dateNumber(cutoff) - 1) } });
    }
    if (!recurrence) {
      await tx.activityEvent.update({ where: { id: eventId }, data: { title: input.title, activityType: input.activityType, startsAt: new Date(input.startsAt), endsAt: new Date(Date.parse(input.startsAt) + input.durationMinutes * 60_000), locationName: input.locationName, latitude: input.latitude, longitude: input.longitude, note: input.note, participationMode: input.participationMode, seriesId: null, seriesException: true } });
      await cancelActivityEvents(tx, events.filter((event) => event.id !== eventId), actorId);
      return;
    }
    const definition = seriesDefinition(input, recurrence);
    const selectedDate = definition.startDate;
    const shiftDays = dateNumber(selectedDate) - dateNumber(selected.occurrenceDate!);
    const anchorDate = scope === "series" ? dateAt(dateNumber(family[0].startDate) + shiftDays) : selectedDate;
    const next = await tx.groupActivitySeries.create({ data: { ...definition, startDate: anchorDate, familyId: old.familyId, creatorId: actorId, groupId: old.groupId, visibility: old.visibility } });
    const targetIDs = events.map((event) => event.id);
    const dates = events.map((event) => dateAt(dateNumber(event.occurrenceDate!) + shiftDays));
    const collision = await tx.activityEvent.findFirst({ where: { seriesFamilyId: old.familyId, occurrenceDate: { in: dates }, id: { notIn: targetIDs } }, select: { id: true } });
    if (collision) throw new SeriesError(422, "The revised dates overlap an occurrence outside the selected scope.");
    // Free the unique slot keys together before a date shift (for example,
    // moving every Saturday forward one week into the next existing slot).
    await tx.activityEvent.updateMany({ where: { id: { in: targetIDs } }, data: { occurrenceDate: null } });
    const retained = new Set<string>();
    // The selected occurrence follows an explicitly changed first date.
    await tx.activityEvent.update({ where: { id: eventId }, data: { ...eventData(next, selectedDate), startsAt: new Date(input.startsAt), endsAt: new Date(Date.parse(input.startsAt) + input.durationMinutes * 60_000), seriesException: false } });
    retained.add(selectedDate);
    for (const event of events.filter((event) => event.id !== eventId)) {
      const date = dateAt(dateNumber(event.occurrenceDate!) + shiftDays);
      if (scheduledDate(next, date) && !retained.has(date) && eventData(next, date).startsAt > new Date()) {
        await tx.activityEvent.update({ where: { id: event.id }, data: { ...eventData(next, date), seriesException: event.status === "cancelled" } });
        retained.add(date);
      } else {
        await tx.activityEvent.update({ where: { id: event.id }, data: { occurrenceDate: date, seriesException: true } });
        await cancelActivityEvents(tx, [event], actorId);
      }
    }
    await materialize(tx, next);
  });
}

async function assertSeriesManager(db: Database, series: Pick<GroupActivitySeries, "groupId">, userId: string, requireScheduling = false) {
  const group = await lockedGroup(db, series.groupId);
  const member = await db.groupMember.findUnique({ where: { groupId_userId: { groupId: series.groupId, userId } }, select: { status: true, role: true } });
    if (member?.status !== "active" || (requireScheduling && (group.lifecycle === "archived" || !group.scheduledActivitiesEnabled))) throw new SeriesError(403, "Active Group membership and scheduled activities are required.");
  const members = await db.groupMember.findMany({ where: { groupId: group.id, status: "active" }, select: { userId: true } });
  const blocked = await db.socialBlock.findFirst({ where: { OR: members.flatMap((m) => [{ blockerId: userId, blockedId: m.userId }, { blockerId: m.userId, blockedId: userId }]) }, select: { id: true } });
  if (blocked) throw new SeriesError(403, "This Group is unavailable.");
  return { group, member };
}

export async function cancelActivitySeries(eventId: string, actorId: string, scope: "this" | "following" | "series") {
  await seriesTransaction(async (tx) => {
    const selected = await tx.activityEvent.findUnique({ where: { id: eventId } });
    if (!selected?.seriesId || selected.creatorId !== actorId) throw new SeriesError(403, "Only the organizer can cancel this activity.");
    if (selected.status === "cancelled" && scope === "this") return;
    if (!["scheduled", "cancelled"].includes(selected.status) || selected.startsAt <= new Date()) throw new SeriesError(409, "Only future activities can be cancelled.");
    if (await tx.activityEventParticipant.findFirst({ where: { activityEventId: selected.id, startedAt: { not: null } }, select: { id: true } })) throw new SeriesError(409, "Activities with recorded participation cannot be cancelled.");
    const series = await tx.groupActivitySeries.findUniqueOrThrow({ where: { id: selected.seriesId } });
    await assertSeriesManager(tx, series, actorId);
    if (scope === "this") {
      await tx.activityEvent.update({ where: { id: eventId }, data: { seriesException: true } });
      await cancelActivityEvents(tx, [selected], actorId);
      return;
    }
    const family = await tx.groupActivitySeries.findMany({ where: { familyId: series.familyId } });
    for (const segment of family) {
      if (scope === "series" || segment.startDate >= selected.occurrenceDate!) await tx.groupActivitySeries.update({ where: { id: segment.id }, data: { stopped: true } });
      else if (!segment.untilDate || segment.untilDate >= selected.occurrenceDate!) await tx.groupActivitySeries.update({ where: { id: segment.id }, data: { untilDate: dateAt(dateNumber(selected.occurrenceDate!) - 1) } });
    }
    const events = await tx.activityEvent.findMany({ where: { seriesFamilyId: series.familyId, status: "scheduled", startsAt: { gt: new Date() }, participants: { none: { startedAt: { not: null } } }, ...(scope === "following" ? { occurrenceDate: { gte: selected.occurrenceDate! } } : {}) } });
    await cancelActivityEvents(tx, events, actorId);
  });
}
