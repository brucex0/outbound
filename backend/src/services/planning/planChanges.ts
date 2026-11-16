import { raceTaperDays } from "./raceRoadmap.js";
import { createHash } from "node:crypto";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { getPrismaClient } from "../prisma.js";
import { accountDateLabel, accountTimeZone } from "../accountCalendar.js";
import { lockPlanningUser, json, isOptionalWorkout } from "./persistence.js";
import { planAvailability, planDateExcluded, planPausedOn, requiresRecoverySpacing } from "./planAvailability.js";
import { refreshGeneratedPlanInTransaction } from "./planRefresh.js";
import { assemblePlanningState } from "./planningService.js";
import { canonicalWorkoutSuggestion } from "./workoutEdits.js";

export const planChangeSchema = z.object({
  planId: z.string().min(1).max(160), idempotencyKey: z.string().uuid(),
  reason: z.enum(["schedule", "travel", "weather", "illness", "recovery", "other"]).nullish(),
  change: z.discriminatedUnion("operation", [
    z.object({ operation: z.literal("move"), workoutId: z.string().min(1).max(160), toDate: z.string().date() }).strict(),
    z.object({ operation: z.literal("availability"), fromDate: z.string().date().nullable(), throughDate: z.string().date().nullable(), availableDays: z.array(z.number().int().min(1).max(7)).max(7) }).strict(),
    z.object({ operation: z.literal("pause"), fromDate: z.string().date(), reminderDate: z.string().date().nullable() }).strict(),
    z.object({ operation: z.literal("resume") }).strict(),
    z.object({ operation: z.literal("rebuild") }).strict(),
    z.object({ operation: z.literal("undo"), commandId: z.string().min(1).max(160) }).strict(),
  ]),
}).strict();
export const planChangeApplySchema = z.object({ previewId: z.string().min(1).max(160), idempotencyKey: z.string().uuid() }).strict();
type Input = z.infer<typeof planChangeSchema>;
type DB = Prisma.TransactionClient;
const include = { blocks: { orderBy: { sortOrder: "asc" as const }, include: { steps: { orderBy: { sortOrder: "asc" as const } } } } };
type Row = Prisma.PlannedWorkoutGetPayload<{ include: typeof include }>;
type Version = Prisma.TrainingPlanVersionGetPayload<{}>;
type Snapshot = { constraints: Prisma.JsonValue; phase: string; version: Version | null; rows: Row[] };
export class PlanChangeError extends Error { constructor(readonly status: 409 | 422, readonly code: string) { super(code); } }
function fail(code: string, status: 409 | 422 = 422): never { throw new PlanChangeError(status, code); }
const key = (date: Date) => date.toISOString().slice(0, 10);
const hash = (value: unknown) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const packed = (value: unknown) => JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
const record = (value: unknown): Record<string, unknown> => value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
const unpack = (value: Prisma.JsonValue): Snapshot => {
  const snapshot = value as unknown as Snapshot;
  return { ...snapshot, version: snapshot.version ? { ...snapshot.version, effectiveFrom: new Date(snapshot.version.effectiveFrom), effectiveUntil: snapshot.version.effectiveUntil ? new Date(snapshot.version.effectiveUntil) : null, createdAt: new Date(snapshot.version.createdAt) } : null,
    rows: snapshot.rows.map((row) => ({ ...row, scheduledDate: new Date(row.scheduledDate), createdAt: new Date(row.createdAt), updatedAt: new Date(row.updatedAt) })) };
};
async function active(db: DB, userId: string, planId?: string) {
  const plan = await db.trainingPlan.findFirst({ where: { userId, status: "active", ...(planId ? { id: planId } : {}) }, orderBy: { createdAt: "desc" }, include: { goal: true, versions: { orderBy: { versionNumber: "desc" }, take: 1 } } });
  if (!plan) return fail("plan_changed", 409);
  return plan;
}
async function snapshot(db: DB, userId: string, planId: string, today: Date): Promise<Snapshot> {
  const plan = await active(db, userId, planId);
  const rows = await db.plannedWorkout.findMany({ where: { userId, planVersion: { planId }, scheduledDate: { gte: today }, status: { not: "superseded" } }, orderBy: [{ scheduledDate: "asc" }, { id: "asc" }], include });
  return { constraints: plan.goal.constraints, phase: plan.currentPhase, version: plan.versions[0] ?? null, rows };
}
async function revision(db: DB, userId: string, planId: string, today: Date) {
  const [plan, state, readiness, activity, profile, calibration, feedback, history, timeZone] = await Promise.all([
    active(db, userId, planId), snapshot(db, userId, planId, today),
    db.readinessCheckIn.findFirst({ where: { userId }, orderBy: { date: "desc" } }),
    db.activity.aggregate({ where: { userId }, _max: { updatedAt: true }, _count: true }),
    db.runnerProfile.findUnique({ where: { userId }, select: { updatedAt: true } }),
    db.calibrationProgram.findUnique({ where: { userId }, select: { updatedAt: true } }),
    db.workoutFeedback.findMany({ where: { userId, recordedAt: { gte: new Date(today.getTime() - 14 * 86400000) } }, orderBy: { id: "asc" }, select: { id: true, recordedAt: true, effort: true } }),
    db.plannedWorkout.findMany({ where: { userId, scheduledDate: { gte: new Date(today.getTime() - 90 * 86400000), lt: today }, planVersion: { planId } }, orderBy: { id: "asc" }, select: { id: true, updatedAt: true, status: true, completions: { orderBy: { id: "asc" }, select: { id: true, perceivedEffort: true, completionQuality: true, durationSeconds: true, performedAsIssued: true } } } }),
    accountTimeZone(userId, undefined, db),
  ]);
  return hash({ date: key(today), planUpdatedAt: plan.updatedAt, goalUpdatedAt: plan.goal.updatedAt, state, readiness, activity, profile, calibration, feedback, history, timeZone });
}
const summary = (state: Snapshot) => state.rows.filter((row) => row.status !== "superseded").map((row) => ({ id: row.id, date: key(row.scheduledDate), title: row.title, durationSeconds: row.durationSeconds, optional: isOptionalWorkout(row), status: row.status }));
function previewResponse(command: { id: string; operation: string; before: Prisma.JsonValue; after: Prisma.JsonValue; expiresAt: Date; appliedAt: Date | null }) {
  return { previewId: command.id, operation: command.operation, expiresAt: command.expiresAt, applied: command.appliedAt != null,
    before: summary(unpack(command.before)), after: summary(unpack(command.after)), availability: planAvailability(unpack(command.after).constraints) };
}

export async function planChangeContext(userId: string) {
  return getPrismaClient().$transaction(async (db) => {
    await lockPlanningUser(db, userId);
    const plan = await active(db, userId); const today = accountDateLabel(new Date(), await accountTimeZone(userId, undefined, db));
    const state = await snapshot(db, userId, plan.id, today);
    const last = await db.planChangeCommand.findFirst({ where: { userId, planId: plan.id, appliedAt: { not: null }, undoneAt: null, operation: { not: "undo" } }, orderBy: { appliedAt: "desc" } });
    const canUndo = last && last.validForDate === key(today) && last.resultRevision === await revision(db, userId, plan.id, today);
    return { planId: plan.id, today: key(today), timeZone: await accountTimeZone(userId, undefined, db), workouts: summary(state), availability: planAvailability(state.constraints), undoCommandId: canUndo ? last.id : null };
  }, { timeout: 30_000 });
}

/** Preview uses only transaction-local engine writes and rolls them back before saving its receipt. */
export async function previewPlanChange(userId: string, input: Input) {
  return getPrismaClient().$transaction(async (db) => {
    await lockPlanningUser(db, userId);
    const requestHash = hash(input);
    const existing = await db.planChangeCommand.findUnique({ where: { userId_idempotencyKey: { userId, idempotencyKey: input.idempotencyKey } } });
    if (existing) { if (existing.requestHash !== requestHash) fail("key_reused", 409); return previewResponse(existing); }
    const plan = await active(db, userId, input.planId); const now = new Date();
    const today = accountDateLabel(now, await accountTimeZone(userId, undefined, db));
    const before = await snapshot(db, userId, plan.id, today); const baseRevision = await revision(db, userId, plan.id, today);
    const change = input.change; const constraints = record(before.constraints); let availability = { ...planAvailability(constraints) };
    let after: Snapshot;
    await db.$executeRawUnsafe("SAVEPOINT plan_change_preview");
    try {
      if (change.operation === "undo") {
        const command = await db.planChangeCommand.findFirst({ where: { id: change.commandId, userId, planId: plan.id, appliedAt: { not: null }, undoneAt: null, operation: { not: "undo" } } });
        if (!command || command.resultRevision !== baseRevision || command.validForDate !== key(today)) fail("undo_changed", 409);
        const original = unpack(command.before);
        after = { ...original, version: before.version, rows: original.rows.filter((row) => row.scheduledDate >= today).map((row) => row.status === "planned" ? { ...row, prescription: { ...record(row.prescription), planAdjustmentPinned: true } } : row) };
      } else {
        if (change.operation === "move") {
          if (planPausedOn(constraints, today)) fail("plan_paused");
          const source = before.rows.find((row) => row.id === change.workoutId && row.status === "planned" && !isOptionalWorkout(row));
          if (!source || change.toDate < key(today) || change.toDate === key(source.scheduledDate)) fail("invalid_move");
          const target = new Date(`${change.toDate}T00:00:00Z`);
          // Keep moves in the currently reviewed horizon; event dates/taper boundaries never shift.
          const last = before.rows.reduce((date, row) => row.scheduledDate > date ? row.scheduledDate : date, today);
          if (target > last || planDateExcluded(constraints, target)) fail("invalid_move");
          if (plan.goal.targetDate) {
            const event = key(plan.goal.targetDate); const taper = new Date(plan.goal.targetDate.getTime() - raceTaperDays(plan.goal) * 86400000);
            if (change.toDate >= event || key(source.scheduledDate) >= event || (source.scheduledDate < taper) !== (target < taper)) fail("event_boundary");
          }
          const sourceKey = key(source.scheduledDate);
          const moved = before.rows.map((row) => row.status !== "planned" ? row : key(row.scheduledDate) === sourceKey ? { ...row, scheduledDate: target } : key(row.scheduledDate) === change.toDate ? { ...row, scheduledDate: source.scheduledDate } : row);
          // Do not add a required slot on a day already closed by completion/skip.
          if (before.rows.some((row) => ["completed", "skipped"].includes(row.status) && [sourceKey, change.toDate].includes(key(row.scheduledDate)) && !isOptionalWorkout(row))) fail("closed_day");
          const required = moved.filter((row) => row.status === "planned" && !isOptionalWorkout(row) && row.modality === "run");
          const recentClosed = await db.plannedWorkout.findMany({ where: { userId, planVersion: { planId: plan.id }, status: "completed", modality: "run", scheduledDate: { gte: new Date(today.getTime() - 2 * 86400000), lt: today } }, select: { id: true, scheduledDate: true, stimulus: true } });
          const spacingRows = [...required, ...recentClosed];
          const changed = required.filter((row) => [sourceKey, change.toDate].includes(key(row.scheduledDate)));
          if (changed.some((row) => spacingRows.some((other) => other.id !== row.id && Math.abs(other.scheduledDate.getTime() - row.scheduledDate.getTime()) < 2 * 86400000 && requiresRecoverySpacing(row, other)))) fail("recovery_spacing");
          after = { ...before, rows: moved.map((row) => row.status === "planned" && [sourceKey, change.toDate].includes(key(row.scheduledDate)) ? { ...row, prescription: { ...record(row.prescription), planAdjustmentPinned: true, planAdjustmentReservedDates: [...new Set([...(Array.isArray(record(row.prescription).planAdjustmentReservedDates) ? record(row.prescription).planAdjustmentReservedDates as string[] : []), key(before.rows.find((item) => item.id === row.id)!.scheduledDate)])] } } : row) };
        } else {
          if (change.operation === "pause") {
            if ((change.fromDate < key(today) && change.fromDate !== availability.pausedOn) || (change.reminderDate && change.reminderDate < change.fromDate)) fail("invalid_pause");
            availability = { ...availability, paused: true, pausedOn: change.fromDate, reminderDate: change.reminderDate };
          } else if (change.operation === "availability") {
            if ((change.fromDate == null) !== (change.throughDate == null) || (change.fromDate && (change.fromDate < key(today) || change.throughDate! < change.fromDate || new Date(change.throughDate!).getTime() - new Date(change.fromDate).getTime() > 90 * 86400000))) fail("invalid_range");
            availability = { ...availability, unavailableFrom: change.fromDate ?? undefined, unavailableThrough: change.throughDate ?? undefined, availableDays: change.fromDate ? [...new Set(change.availableDays)] : undefined };
          } else if (change.operation === "resume") {
            if (!availability.paused) fail("not_paused");
            availability = { ...availability, paused: false, pausedOn: undefined, reminderDate: null };
          } else if (planPausedOn({ planAvailability: availability }, today)) fail("plan_paused");
          await db.trainingGoal.update({ where: { id: plan.goalId }, data: { constraints: packed({ ...constraints, planAvailability: availability }) } });
          if (change.operation === "pause" || change.operation === "availability" && change.fromDate != null) {
            const excluded = before.rows.filter((row) => row.status === "planned" && planDateExcluded({ planAvailability: availability }, row.scheduledDate));
            await db.plannedWorkout.updateMany({ where: { id: { in: excluded.map((row) => row.id) }, status: "planned" }, data: { status: "superseded" } });
          }
          if ((change.operation !== "pause" || planAvailability(before.constraints).paused) && !planPausedOn({ planAvailability: availability }, today)) {
            // Full athlete/readiness-aware production engine. No elapsed/missed workouts are caught up.
            await refreshGeneratedPlanInTransaction(db, userId, now, true, change.operation === "resume", true);
          }
          after = await snapshot(db, userId, plan.id, today);
          if (["resume", "rebuild"].includes(change.operation) && after.version?.id === before.version?.id) fail("rebuild_unavailable");
        }
      }
    } finally { await db.$executeRawUnsafe("ROLLBACK TO SAVEPOINT plan_change_preview"); await db.$executeRawUnsafe("RELEASE SAVEPOINT plan_change_preview"); }
    const command = await db.planChangeCommand.create({ data: { userId, planId: plan.id, idempotencyKey: input.idempotencyKey, requestHash, operation: change.operation, reason: input.reason ?? null,
      baseRevision, validForDate: key(today), expiresAt: new Date(now.getTime() + 15 * 60_000), before: packed(before), after: packed(after!), } });
    console.info("[planning] plan_change_preview", { operation: change.operation, result: "ready" });
    return previewResponse(command);
  }, { timeout: 60_000 });
}

async function materialize(db: DB, userId: string, planId: string, before: Snapshot, after: Snapshot) {
  const plan = await active(db, userId, planId);
  if (after.version && after.version.id !== before.version?.id) {
    const { createdAt: _created, ...data } = after.version;
    await db.trainingPlanVersion.create({ data: { ...data, engineInputs: data.engineInputs as Prisma.InputJsonValue, engineDecision: data.engineDecision as Prisma.InputJsonValue } });
  }
  const afterIDs = new Set(after.rows.map((row) => row.id));
  await db.plannedWorkout.updateMany({ where: { id: { in: before.rows.filter((row) => row.status === "planned" && !afterIDs.has(row.id)).map((row) => row.id) }, userId, status: "planned" }, data: { status: "superseded" } });
  const beforeIDs = new Set(before.rows.map((row) => row.id));
  for (const row of after.rows) {
    const data = { scheduledDate: row.scheduledDate, status: row.status, prescription: row.prescription as Prisma.InputJsonValue };
    if (beforeIDs.has(row.id) || await db.plannedWorkout.findUnique({ where: { id: row.id }, select: { id: true } })) {
      const prior = before.rows.find((item) => item.id === row.id);
      if (!prior || hash([prior.scheduledDate, prior.status, prior.prescription]) !== hash([row.scheduledDate, row.status, row.prescription])) await db.plannedWorkout.update({ where: { id: row.id }, data });
    } else {
      await db.plannedWorkout.create({ data: { id: row.id, userId, planVersionId: row.planVersionId, ...data, modality: row.modality, stimulus: row.stimulus, title: row.title, durationSeconds: row.durationSeconds, distanceMeters: row.distanceMeters, targetCalories: row.targetCalories,
        intensityModel: row.intensityModel, intensityTarget: row.intensityTarget === null ? Prisma.JsonNull : row.intensityTarget as Prisma.InputJsonValue, isKeyWorkout: row.isKeyWorkout, replacesWorkoutId: row.replacesWorkoutId,
        blocks: { create: row.blocks.map((block) => ({ id: block.id, sortOrder: block.sortOrder, blockType: block.blockType, modality: block.modality, stimulus: block.stimulus, durationSeconds: block.durationSeconds, distanceMeters: block.distanceMeters, repeats: block.repeats, restSeconds: block.restSeconds, metadata: block.metadata as Prisma.InputJsonValue,
          steps: { create: block.steps.map((step) => ({ id: step.id, sortOrder: step.sortOrder, label: step.label, kind: step.kind, durationSeconds: step.durationSeconds, distanceMeters: step.distanceMeters, target: step.target === null ? Prisma.JsonNull : step.target as Prisma.InputJsonValue, detail: step.detail })) } })) } } });
    }
  }
  await db.trainingGoal.update({ where: { id: plan.goalId }, data: { constraints: after.constraints as Prisma.InputJsonValue } });
  await db.trainingPlan.update({ where: { id: planId }, data: { currentPhase: after.phase } });
}
export async function applyPlanChange(userId: string, input: z.infer<typeof planChangeApplySchema>) {
  return getPrismaClient().$transaction(async (db) => {
    await lockPlanningUser(db, userId);
    const command = await db.planChangeCommand.findFirst({ where: { id: input.previewId, userId, idempotencyKey: input.idempotencyKey } });
    if (!command) fail("preview_missing", 409);
    const now = new Date(); const today = accountDateLabel(now, await accountTimeZone(userId, undefined, db));
    if (!command.appliedAt) {
      const plan = await active(db, userId, command.planId);
      if (command.expiresAt < now || command.validForDate !== key(today)) fail("preview_expired", 409);
      if (command.baseRevision !== await revision(db, userId, plan.id, today)) fail("preview_stale", 409);
      const before = unpack(command.before), after = unpack(command.after);
      await materialize(db, userId, plan.id, before, after);
      const resultRevision = await revision(db, userId, plan.id, today);
      await db.planChangeCommand.update({ where: { id: command.id }, data: { appliedAt: now, resultRevision } });
      if (command.operation === "undo") {
        // The exact prior revision identifies the only undoable command.
        await db.planChangeCommand.updateMany({ where: { userId, planId: plan.id, resultRevision: command.baseRevision, undoneAt: null }, data: { undoneAt: now } });
      }
      await db.planAdjustmentEvent.create({ data: { userId, planId: plan.id, fromVersionId: before.version?.id, toVersionId: after.version?.id,
        eventType: "explicitPlanChange", message: "plan.adjust.applied", changedWorkoutIds: after.rows.filter((row) => row.status === "planned").map((row) => row.id), engineDecision: json({ operation: command.operation }) } });
      console.info("[planning] plan_change_apply", { operation: command.operation, result: "applied" });
    }
    return { receipt: { id: command.id, operation: command.operation }, state: await assemblePlanningState(userId, "updated", db), activitySuggestion: await canonicalWorkoutSuggestion(db, userId, "updated", now) };
  }, { timeout: 60_000 });
}
