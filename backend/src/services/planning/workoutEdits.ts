import { issueWorkout, withIssuanceTransaction } from "./workoutIssuance.js";
import { createHash, randomUUID } from "node:crypto";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { standaloneWorkoutCatalog, type StandaloneWorkoutCatalogItem } from "../../data/standaloneWorkouts.js";
import { getPrismaClient } from "../prisma.js";
import { applyDailyWorkoutAdjustment, latestReadinessId, suggestionFingerprint, restFingerprint } from "../personalization/workoutAdjustmentPolicy.js";
import { buildBaseActivitySuggestion } from "./activitySuggestion.js";
import { assemblePlanningState } from "./planningService.js";
import { json, lockPlanningUser } from "./persistence.js";
import { refreshGeneratedPlanInTransaction } from "./planRefresh.js";
import type { ActivitySuggestion, ActivitySuggestionResponse, WorkoutEditContext, PlanningStatus } from "./types.js";

const targetSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("time"), seconds: z.number().int().min(300).max(21_600) }).strict(),
  z.object({ kind: z.literal("distance"), meters: z.number().min(100).max(50_000) }).strict(),
]);
const editsSchema = z.object({ target: targetSchema.optional(), effortPreset: z.enum(["veryEasy", "easy", "steady"]).optional() }).strict();
export const workoutEditApplySchema = z.object({
  plannedWorkoutId: z.string().max(160).nullable(), suggestionId: z.string().min(1).max(160),
  validForDate: z.string().date(), baseRevision: z.string().length(64), idempotencyKey: z.string().uuid(),
  reason: z.enum(["lessTime", "lowEnergy", "soreness", "other"]).nullish(),
  change: z.discriminatedUnion("operation", [
    z.object({ operation: z.literal("edit"), edits: editsSchema.refine((value) => value.target || value.effortPreset, "Choose a field to change.") }).strict(),
    z.object({ operation: z.literal("replace"), catalogWorkoutId: z.string().min(1).max(160), catalogVersion: z.number().int().positive(), edits: editsSchema.optional() }).strict(),
    z.object({ operation: z.literal("skip") }).strict(),
  ]),
}).strict();
export type WorkoutEditApplyInput = z.infer<typeof workoutEditApplySchema>;
export class WorkoutEditError extends Error {
  constructor(readonly status: 409 | 422, message: string) { super(message); }
}
const presets = [{ id: "veryEasy", min: 1, max: 2 }, { id: "easy", min: 2, max: 4 }, { id: "steady", min: 4, max: 6 }];
type DB = Prisma.TransactionClient;
const hash = (value: unknown) => createHash("sha256").update(stable(value)).digest("hex");
function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).filter(([, v]) => v !== undefined).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${JSON.stringify(k)}:${stable(v)}`).join(",")}}`;
  return JSON.stringify(value) ?? "null";
}
const workoutInclude = { blocks: { orderBy: { sortOrder: "asc" as const }, include: { steps: { orderBy: { sortOrder: "asc" as const } } } } };

/** A normalized effective structure, excluding mutable DB timestamps and row IDs. */
async function structure(db: DB, userId: string, primary: ActivitySuggestion | null) {
  if (!primary?.plannedWorkoutId) return primary?.effectiveWorkout ?? primary?.catalogWorkout ?? null;
  const workout = await db.plannedWorkout.findFirst({ where: { id: primary.plannedWorkoutId, userId }, include: workoutInclude });
  if (!workout) return null;
  return { title: workout.title, modality: workout.modality, stimulus: workout.stimulus, status: workout.status,
    durationSeconds: workout.durationSeconds, distanceMeters: workout.distanceMeters, targetCalories: workout.targetCalories,
    intensityModel: workout.intensityModel, intensityTarget: workout.intensityTarget, prescription: workout.prescription,
    blocks: workout.blocks.map((b) => ({ blockType: b.blockType, modality: b.modality, stimulus: b.stimulus,
      durationSeconds: b.durationSeconds, distanceMeters: b.distanceMeters, repeats: b.repeats, restSeconds: b.restSeconds, metadata: b.metadata,
      steps: b.steps.map((s) => ({ label: s.label, kind: s.kind, durationSeconds: s.durationSeconds, distanceMeters: s.distanceMeters, target: s.target, detail: s.detail })) })) };
}
async function revision(db: DB, userId: string, response: ActivitySuggestionResponse) {
  const { workoutEditId: _id, workoutRevision: _rev, performedWorkoutReference: _issued, ...primary } = response.primary ?? {};
  return hash({ date: response.validForDate, plan: response.planContext, primary, structure: await structure(db, userId, response.primary),
    readiness: await latestReadinessId(db, userId), activity: response.activityWatermark, safety: response.decision.safetyFlags });
}

function capabilities(primary: ActivitySuggestion, effective: StandaloneWorkoutCatalogItem): Omit<WorkoutEditContext, "baseRevision"> {
  // Editing never removes interval phases, pace/HR/power targets, or run/walk intent.
  const hasUnsupportedTarget = !["rpe", "effort"].includes(primary.intensityModel) || primary.targetCalories != null
    || effective.steps.some((step) => step.coachingTarget?.pace != null);
  const main = effective.steps.filter((step) => !["warmup", "cooldown"].includes(step.coachingTarget?.phase ?? "easy"));
  const structured = effective.guideInstructions.segments.length !== effective.steps.length || primary.runWalk === true || ["speed", "threshold"].includes(primary.stimulus) || main.length !== 1 || main.some((s) => ["work", "walk", "open"].includes(s.coachingTarget?.phase ?? "easy"));
  const editable = !hasUnsupportedTarget && !structured;
  const fixedSeconds = effective.steps.filter((s) => ["warmup", "cooldown"].includes(s.coachingTarget?.phase ?? "easy")).reduce((n, s) => n + s.durationSeconds, 0);
  const mainIndex = effective.steps.findIndex((s) => !["warmup", "cooldown"].includes(s.coachingTarget?.phase ?? "easy"));
  const effort = effective.guideInstructions.segments[Math.max(0, mainIndex)]?.effort;
  return { canEditTarget: editable, canEditEffort: editable, canConvertGoal: editable && effective.steps.length === 1,
    limitation: hasUnsupportedTarget ? "unsupportedTargets" : structured ? "structuredWorkout" : null,
    minimumDurationSeconds: Math.max(300, fixedSeconds + 60), maximumDurationSeconds: 21_600,
    minimumDistanceMeters: 100, maximumDistanceMeters: 50_000, effortPresets: editable ? presets : [],
    currentEffortPreset: presets.find((p) => effort?.rpeMin === p.min && effort?.rpeMax === p.max)?.id ?? null };
}

/** These server-owned adaptive paths replace a slot's execution content, not its identity. */
function isAdaptivePlannedPrescription(primary: ActivitySuggestion): boolean {
  if (!primary.plannedWorkoutId) return false;
  if (["recovery-run-25", "recovery-spin-25"].includes(primary.archetypeId ?? "")) return primary.id === primary.archetypeId;
  return primary.archetypeId === "easy-run-observed-baseline" && primary.id === `observed-baseline-${primary.plannedWorkoutId}`;
}

/** Make a guide from the real prescription, preserving each phase and target. */
export async function effectiveWorkout(db: DB, userId: string, primary: ActivitySuggestion): Promise<StandaloneWorkoutCatalogItem> {
  if (primary.effectiveWorkout) return structuredClone(primary.effectiveWorkout);
  if (primary.catalogWorkout) return structuredClone(primary.catalogWorkout);
  // An adaptive recommendation still references the original slot for Apply/audit,
  // but its reviewed recovery/easy phases have already replaced that slot's tempo/interval content.
  const workout = primary.plannedWorkoutId && !isAdaptivePlannedPrescription(primary)
    ? await db.plannedWorkout.findFirst({ where: { id: primary.plannedWorkoutId, userId }, include: workoutInclude }) : null;
  const rpe = (primary.intensityTarget ?? {}) as { min?: number; max?: number };
  let steps: StandaloneWorkoutCatalogItem["steps"] = workout?.blocks.flatMap((block) => block.steps.length ? block.steps.map((step, index) => ({
    id: `${block.sortOrder}-${index}`, label: step.label, durationSeconds: step.durationSeconds ?? block.durationSeconds ?? 0,
    detail: step.detail ?? undefined,
    coachingTarget: { phase: phase(step.kind, block.blockType), recognizesTargetLock: false,
      ...(readPace(step.target) ? { pace: readPace(step.target)!,
        ...((step.target as Record<string, unknown> | null)?.paceEstimatePolicy === "reported-maximal-running-v1" ? { paceEstimatePolicy: "reported-maximal-running-v1" } : {}) } : {}) },
  })) : [{ id: `${block.sortOrder}`, label: block.blockType, durationSeconds: block.durationSeconds ?? 0,
    coachingTarget: { phase: phase(block.blockType, block.blockType), recognizesTargetLock: false } }]) ?? [{ id: "main", label: primary.title,
    durationSeconds: primary.durationSeconds ?? primary.durationMinutes * 60,
    coachingTarget: { phase: "easy", recognizesTargetLock: false } }];
  if (!workout && primary.steps.length > 1) {
    const continuous = ["easy-run-30", "easy-run-observed-baseline", "recovery-run-25", "easy-ride-35", "easy-walk-25"].includes(primary.archetypeId ?? primary.id);
    steps = primary.steps.map((label, index) => ({ id: `phase-${index}`, label,
      durationSeconds: Number(label.match(/^(\d+) min/)?.[1] ?? 0) * 60,
      coachingTarget: { phase: continuous ? index === 0 ? "warmup" : index === primary.steps.length - 1 ? "cooldown" : "easy" : "work", recognizesTargetLock: false } }));
  }
  const phaseTargets = workout?.blocks.flatMap((b) => b.steps.length ? b.steps.map((s) => s.target) : [null]) ?? [];
  let elapsed = 0;
  return { id: primary.archetypeId ?? primary.id, title: primary.title, subtitle: primary.effortLabel, durationLabel: "",
    systemImage: primary.modality === "bike" ? "bicycle" : "figure.run", sport: primary.modality === "bike" ? "bike" : primary.modality === "walk" ? "walk" : "run",
    category: "easy", detail: primary.why, guideLine: primary.why, startLabel: primary.startLabel,
    ...(primary.distanceMeters != null ? { targetDistanceMeters: primary.distanceMeters } : { targetDurationSeconds: primary.durationSeconds ?? primary.durationMinutes * 60 }),
    steps, prerequisites: [], sourceRefs: [], guideInstructions: { objective: primary.why, beforeStart: [], finish: [],
      stopConditions: ["Stop if you feel pain, dizziness, or unusual discomfort."],
      segments: steps.map((step, index) => { const startSeconds = elapsed; elapsed += step.durationSeconds;
        const target = phaseTargets[index] as { rpe?: number | number[]; min?: number; max?: number } | undefined;
        const values = typeof target?.rpe === "number" ? [target.rpe, target.rpe] : target?.rpe;
        return {
        id: step.id, trigger: primary.distanceMeters != null && steps.length === 1
          ? { type: "distance" as const, startMeters: 0, endMeters: primary.distanceMeters }
          : { type: "elapsed_time" as const, startSeconds, endSeconds: elapsed },
        effort: { rpeMin: values?.[0] ?? target?.min ?? rpe.min ?? 2, rpeMax: values?.[1] ?? target?.max ?? rpe.max ?? 4, feel: primary.effortLabel },
        instruction: step.detail ?? step.label, cue: step.label, fallback: step.detail ?? step.label,
      }; }) } };
}
/** Only the unchanged current edit may supply its retained effective execution tree. */
export async function storedEffectiveWorkout(db: DB, userId: string, primary: ActivitySuggestion): Promise<StandaloneWorkoutCatalogItem> {
  if (primary.plannedWorkoutId) {
    const row = await db.plannedWorkout.findFirst({ where: { id: primary.plannedWorkoutId, userId }, select: { prescription: true } });
    const editId = (row?.prescription as Record<string, unknown> | undefined)?.workoutEditId;
    const edit = typeof editId === "string" ? await db.workoutEdit.findFirst({ where: { id: editId, userId, plannedWorkoutId: primary.plannedWorkoutId, operation: { not: "skip" } } }) : null;
    const context = edit?.validationContext as { resultStructureHash?: string } | undefined;
    if (context?.resultStructureHash && context.resultStructureHash === hash(await structure(db, userId, primary))) {
      const after = edit?.afterWorkout as unknown as { effectiveWorkout?: StandaloneWorkoutCatalogItem };
      if (after?.effectiveWorkout) return structuredClone(after.effectiveWorkout);
    }
  }
  return effectiveWorkout(db, userId, primary);
}
function phase(kind: string, block: string): "warmup" | "cooldown" | "work" | "walk" | "recovery" | "easy" {
  if (/warm/i.test(kind + block)) return "warmup";
  if (/cool/i.test(kind + block)) return "cooldown";
  if (/interval|tempo|threshold|speed|fartlek|hill|^work$|repeat/i.test(kind) || /interval|repeat/i.test(block)) return "work";
  if (/walk/i.test(kind + block)) return "walk";
  if (/recover/i.test(kind + block)) return "recovery";
  return "easy";
}
function readPace(value: unknown): NonNullable<StandaloneWorkoutCatalogItem["coachingTarget"]>["pace"] | undefined {
  const target = value as Record<string, unknown> | null;
  if (target?.pace && typeof target.pace === "object") return target.pace as NonNullable<StandaloneWorkoutCatalogItem["coachingTarget"]>["pace"];
  return undefined;
}
async function checkedCapabilities(db: DB, userId: string, primary: ActivitySuggestion, effective: StandaloneWorkoutCatalogItem) {
  const result = capabilities(primary, effective);
  // Original slot targets belong in revision/audit, not capability checks for
  // the explicitly selected adaptive prescription. Ordinary canonical rows retain all guards below.
  if (!primary.plannedWorkoutId || isAdaptivePlannedPrescription(primary)) return result;
  const raw = await db.plannedWorkout.findFirst({ where: { id: primary.plannedWorkoutId, userId }, include: workoutInclude });
  const unsafeDistance = raw && (raw.blocks.length !== 1 || primary.distanceMeters == null)
    && raw.blocks.some((b) => b.distanceMeters != null || b.steps.some((s) => s.distanceMeters != null));
  const unsafe = unsafeDistance || raw?.blocks.some((b) => /threshold|speed/.test(b.stimulus) || /run.walk/i.test(JSON.stringify(b.steps.map((s) => s.label))) || (b.repeats ?? 1) > 1 || (b.restSeconds ?? 0) > 0 || b.steps.some((s) => {
    const target = s.target as Record<string, unknown> | null;
    return target && Object.keys(target).some((key) => !["rpe", "min", "max", "phase", "recognizesTargetLock"].includes(key));
  }));
  return unsafe ? { ...result, canEditTarget: false, canEditEffort: false, canConvertGoal: false, effortPresets: [], limitation: "unsupportedTargets" as const } : result;
}

export async function applyManualWorkoutOverride(db: DB, userId: string, baseline: ActivitySuggestionResponse): Promise<ActivitySuggestionResponse> {
  // Inspect only the newest edit. An invalidated newer edit never resurrects an older one.
  const edit = await db.workoutEdit.findFirst({ where: { userId, validForDate: baseline.validForDate }, orderBy: [{ createdAt: "desc" }, { id: "desc" }] });
  if (!edit) return baseline;
  const laterLegacyCommand = await db.personalizationAdjustment.findFirst({ where: { userId, status: "applied", policyVersion: "workout-adjustment-apply-v1", decidedAt: { gt: edit.createdAt } }, select: { id: true } });
  if (laterLegacyCommand) return baseline;
  const context = edit.validationContext as { fingerprint: string; readinessId: string | null; planId: string | null; resultStructureHash?: string };
  const skip = edit.operation === "skip";
  if (context.fingerprint !== (skip ? restFingerprint(baseline) : suggestionFingerprint(baseline))
    || context.readinessId !== await latestReadinessId(db, userId) || baseline.decision.safetyFlags.length > 0) return baseline;
  if (!skip && edit.plannedWorkoutId && (!context.resultStructureHash
    || baseline.primary?.plannedWorkoutId !== edit.plannedWorkoutId
    || hash(await structure(db, userId, baseline.primary)) !== context.resultStructureHash)) return baseline;
  const primary = skip ? null : (edit.afterWorkout as unknown as { suggestion: ActivitySuggestion }).suggestion;
  return { ...baseline, workoutEditOperation: edit.operation, primary, alternates: [], status: skip ? "restRecommended" : "suggested", source: "adaptive",
    relationship: skip ? "rest" : baseline.planContext ? "adjustedFromPlan" : "noPlanSuggestion", guideLine: primary?.why ?? "Rest today." };
}
export async function canonicalWorkoutSuggestion(db: DB, userId: string, planningStatus: PlanningStatus = "stable", now: Date = new Date()): Promise<ActivitySuggestionResponse> {
  return withIssuanceTransaction(db, userId, async (db) => {
    const baseline = await buildBaseActivitySuggestion(userId, planningStatus, now, db);
    const legacy = await applyDailyWorkoutAdjustment(db, userId, baseline);
    // Manual fingerprints refer to the base DB prescription; legacy proposals cannot mask a direct edit.
    const manual = await applyManualWorkoutOverride(db, userId, baseline);
    const response = await attachWorkoutEditContext(db, userId, manual !== baseline ? manual : legacy);
    const issue = async (primary: ActivitySuggestion | null) => {
      if (!primary?.plannedWorkoutId) return primary;
      const effective = await effectiveWorkout(db, userId, primary);
      const performedWorkoutReference = await issueWorkout(db, userId, primary.plannedWorkoutId, { primary, effective, replacement: isAdaptivePlannedPrescription(primary) });
      return { ...primary, effectiveWorkout: effective, ...(performedWorkoutReference ? { performedWorkoutReference } : {}) };
    };
    return { ...response, primary: await issue(response.primary), alternates: await Promise.all(response.alternates.map((row) => issue(row) as Promise<ActivitySuggestion>)) };
  });
}
/** Preserve the provenance of the actual persisted prescription, without restoring an invalidated day overlay. */
async function attachPersistedPlannedEdit(db: DB, userId: string, response: ActivitySuggestionResponse): Promise<ActivitySuggestionResponse> {
  const primary = response.primary;
  if (!primary?.plannedWorkoutId || primary.workoutEditId) return response;
  const row = await db.plannedWorkout.findFirst({ where: { id: primary.plannedWorkoutId, userId, status: "planned" }, select: { prescription: true } });
  const id = (row?.prescription as Record<string, unknown> | undefined)?.workoutEditId;
  if (typeof id !== "string") return response;
  const edit = await db.workoutEdit.findFirst({ where: { id, userId, plannedWorkoutId: primary.plannedWorkoutId, operation: { not: "skip" } } });
  if (!edit) return response;
  const context = edit.validationContext as { resultStructureHash?: string; planId?: string | null };
  const after = edit.afterWorkout as unknown as { suggestion: ActivitySuggestion; effectiveWorkout: StandaloneWorkoutCatalogItem };
  const selected = after.suggestion;
  if (!selected || !context.resultStructureHash || context.planId !== (response.planContext?.planId ?? null)
    || context.resultStructureHash !== hash(await structure(db, userId, primary))) return response;
  const sameSteps = hash(primary.steps) === hash(selected.steps)
    || selected.steps.length === 0 && primary.steps.length === 1 && primary.steps[0] === primary.title;
  if (primary.title !== selected.title || primary.modality !== selected.modality || primary.stimulus !== selected.stimulus
    || (primary.durationSeconds ?? primary.durationMinutes * 60) !== selected.durationSeconds
    || (primary.distanceMeters ?? null) !== (selected.distanceMeters ?? null)
    || (primary.targetCalories ?? null) !== (selected.targetCalories ?? null)
    || primary.intensityModel !== selected.intensityModel || hash(primary.intensityTarget ?? null) !== hash(selected.intensityTarget ?? null)
    || !sameSteps) return response;
  return { ...response, primary: { ...primary, workoutEditId: edit.id, workoutRevision: edit.resultRevision,
    effectiveWorkout: after.effectiveWorkout, catalogWorkout: selected.catalogWorkout, catalogVersion: selected.catalogVersion,
    effortLabel: selected.effortLabel } };
}

export async function attachWorkoutEditContext(db: DB, userId: string, response: ActivitySuggestionResponse): Promise<ActivitySuggestionResponse> {
  if (!response.primary || response.decision.safetyFlags.length) return { ...response, editContext: null };
  response = await attachPersistedPlannedEdit(db, userId, response);
  const primary = response.primary!;
  const effective = await effectiveWorkout(db, userId, primary);
  const allowed = await checkedCapabilities(db, userId, primary, effective);
  // Expose the real phase durations to iOS instead of forcing it to divide plain step labels evenly.
  const enriched: ActivitySuggestionResponse = primary.plannedWorkoutId && !primary.catalogWorkout
    ? { ...response, primary: { ...primary, effectiveWorkout: effective } } : response;
  return { ...enriched, editContext: { ...allowed, baseRevision: await revision(db, userId, enriched) } };
}

export async function applyWorkoutEdit(userId: string, input: WorkoutEditApplyInput) {
  const prisma = getPrismaClient();
  return prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    const now = new Date();
    const requestHash = hash({ ...input, reason: input.reason ?? null });
    const previous = await tx.workoutEdit.findUnique({ where: { userId_idempotencyKey: { userId, idempotencyKey: input.idempotencyKey } } });
    if (previous) {
      if (previous.requestHash !== requestHash) throw new WorkoutEditError(409, "This retry key belongs to another change.");
      return { receipt: { plannedWorkoutId: previous.plannedWorkoutId, workoutEditId: previous.id, revision: previous.resultRevision },
        state: await assemblePlanningState(userId, "stable", tx), activitySuggestion: await canonicalWorkoutSuggestion(tx, userId, "stable", now) };
    }
    await refreshGeneratedPlanInTransaction(tx, userId, now);
    const current = await canonicalWorkoutSuggestion(tx, userId, "stable", now);
    const primary = current.primary;
    if (!primary || current.validForDate !== input.validForDate || primary.id !== input.suggestionId
      || (primary.plannedWorkoutId ?? null) !== input.plannedWorkoutId || current.editContext?.baseRevision !== input.baseRevision
      || current.decision.safetyFlags.length) {
      console.warn("[planning] workout_edit_context_changed", { dateMatches: current.validForDate === input.validForDate,
        suggestionMatches: primary?.id === input.suggestionId, slotMatches: (primary?.plannedWorkoutId ?? null) === input.plannedWorkoutId,
        revisionMatches: current.editContext?.baseRevision === input.baseRevision, safetyFlagCount: current.decision.safetyFlags.length });
      throw new WorkoutEditError(409, "The workout changed. Refresh before editing it.");
    }
    const planned = input.plannedWorkoutId ? await tx.plannedWorkout.findFirst({ where: { id: input.plannedWorkoutId, userId, status: "planned" },
      include: { ...workoutInclude, planVersion: { include: { plan: { include: { versions: { orderBy: { versionNumber: "desc" }, take: 1 } } } } } } }) : null;
    if (input.plannedWorkoutId && (!planned || planned.scheduledDate.toISOString().slice(0, 10) !== input.validForDate
      || planned.planVersion.plan.status !== "active" || (planned.planVersion.plan.versions[0]?.id !== planned.planVersionId
        && typeof (planned.prescription as Record<string, unknown>).workoutEditId !== "string"
        && (planned.prescription as Record<string, unknown>).source !== "explicitWorkoutChange"))) {
      throw new WorkoutEditError(409, "The planned slot changed. Refresh before editing it.");
    }
    const beforeStructure = await structure(tx, userId, primary);
    const skip = input.change.operation === "skip";
    const replacing = input.change.operation === "replace";
    const replacement = input.change.operation === "replace" ? input.change : null;
    const catalog = replacement ? standaloneWorkoutCatalog.workouts.find((w) => w.id === replacement.catalogWorkoutId) : undefined;
    if (replacing && (!catalog || replacement?.catalogVersion !== standaloneWorkoutCatalog.version || catalog.sport !== primary.modality)) {
      throw new WorkoutEditError(409, "The workout catalog changed. Refresh before choosing a workout.");
    }
    let effective = catalog ? structuredClone(catalog) : await effectiveWorkout(tx, userId, primary);
    const edits = input.change.operation === "skip" ? undefined : input.change.edits;
    const replacementStimulus = catalog?.category === "tempo" ? "threshold" : ["speed", "fartlek", "hill"].includes(catalog?.category ?? "") ? "speed" : catalog?.category === "guided_distance" ? "longEndurance" : catalog?.category === "recovery" ? "recovery" : "easyAerobic";
    const selectedPrimary: ActivitySuggestion = catalog ? { ...primary, stimulus: replacementStimulus, runWalk: catalog.category === "walk_run", intensityModel: "rpe", intensityTarget: {}, targetCalories: null, catalogWorkout: catalog } : primary;
    const allowed = catalog ? capabilities(selectedPrimary, effective) : await checkedCapabilities(tx, userId, selectedPrimary, effective);
    if (edits?.target && !allowed.canEditTarget || edits?.effortPreset && !allowed.canEditEffort) {
      throw new WorkoutEditError(422, "This structured workout must keep its phases and targets. Choose another workout instead.");
    }
    if (edits?.target) {
      const target = edits.target;
      const wasDistance = effective.targetDistanceMeters != null;
      if ((target.kind === "distance") !== wasDistance && !allowed.canConvertGoal) throw new WorkoutEditError(422, "This workout cannot change goal type without changing its phases.");
      const seconds = target.kind === "time" ? target.seconds : Math.round(target.meters / 1000 * 420);
      if (seconds < allowed.minimumDurationSeconds) throw new WorkoutEditError(422, "Keep enough time for the warmup and cooldown.");
      const fixed = effective.steps.filter((s) => ["warmup", "cooldown"].includes(s.coachingTarget?.phase ?? "easy")).reduce((n, s) => n + s.durationSeconds, 0);
      effective.steps = effective.steps.map((s) => ["warmup", "cooldown"].includes(s.coachingTarget?.phase ?? "easy") ? s : { ...s, durationSeconds: seconds - fixed });
      effective.targetDistanceMeters = target.kind === "distance" ? target.meters : undefined;
      effective.targetDurationSeconds = target.kind === "time" ? target.seconds : undefined;
      // Duration prose belongs to the new exact goal, while phase names/guide intent remain.
      effective.title = effective.title.replace(/^\d+(?:[.:]\d+)?\s+min\s+/i, "").replace(/(?:\b\d+(?:[.:]\d+)?\s*(?:min(?:ute)?s?|km|K)\b|\s+\d+(?:[.:]\d+)?)$/i, "").trim() || (effective.sport === "bike" ? "Easy ride" : "Easy run");
    }
    const effort = edits?.effortPreset ? presets.find((p) => p.id === edits.effortPreset)! : null;
    if (edits?.target || effort) {
      let elapsed = 0;
      effective.guideInstructions.segments = effective.steps.map((step, index) => {
        const old = effective.guideInstructions.segments[index];
        const startSeconds = elapsed; elapsed += step.durationSeconds;
        return { id: step.id, trigger: effective.targetDistanceMeters != null
          ? { type: "distance", startMeters: 0, endMeters: effective.targetDistanceMeters }
          : { type: "elapsed_time", startSeconds, endSeconds: elapsed },
          effort: effort && !["warmup", "cooldown"].includes(step.coachingTarget?.phase ?? "easy")
            ? { rpeMin: effort.min, rpeMax: effort.max, feel: effort.id === "veryEasy" ? "Very easy" : effort.id === "easy" ? "Easy" : "Steady" }
            : old?.effort ?? { rpeMin: 2, rpeMax: 4, feel: "Easy" },
          instruction: old?.instruction ?? step.detail ?? step.label, cue: old?.cue ?? step.label, fallback: old?.fallback ?? step.label };
      });
      if (effort) {
        const feel = effort.id === "veryEasy" ? "Very easy" : effort.id === "easy" ? "Easy" : "Steady";
        const instruction = effort.id === "veryEasy" ? "Keep the main part very easy and relaxed."
          : effort.id === "easy" ? "Keep the main part comfortable and conversational." : "Keep the main part steady and controlled.";
        const movement = effective.sport === "bike" ? "ride" : effective.sport === "walk" ? "walk" : "run";
        effective.title = `${feel} ${movement}`;
        effective.subtitle = feel;
        effective.guideLine = "Follow your selected effort in the main part. Keep the warmup and cooldown relaxed.";
        effective.guideInstructions.objective = effective.guideLine;
        effective.steps = effective.steps.map((step, index) => {
          if (["warmup", "cooldown"].includes(step.coachingTarget?.phase ?? "easy")) return step;
          effective.guideInstructions.segments[index] = { ...effective.guideInstructions.segments[index], instruction, cue: instruction, fallback: instruction };
          return { ...step, label: effective.title, detail: instruction, transitionInstruction: instruction };
        });
      }
    }
    if (edits?.target) {
      const removeDuration = (text: string) => text.replace(/^\d+(?:[.:]\d+)?\s+min\s+/i, "");
      effective.steps = effective.steps.map((step) => ["warmup", "cooldown"].includes(step.coachingTarget?.phase ?? "easy") ? step : { ...step, label: removeDuration(step.label) });
      effective.guideInstructions.segments = effective.guideInstructions.segments.map((segment) => ({ ...segment,
        instruction: removeDuration(segment.instruction), cue: removeDuration(segment.cue), fallback: removeDuration(segment.fallback) }));
    }
    const id = randomUUID();
    const durationSeconds = effective.targetDistanceMeters != null ? Math.round(effective.targetDistanceMeters / 1000 * 420) : effective.steps.reduce((n, s) => n + s.durationSeconds, 0);
    const after: ActivitySuggestion = { ...primary, title: effective.title, durationSeconds, durationMinutes: Math.ceil(durationSeconds / 60),
      distanceMeters: effective.targetDistanceMeters ?? null, targetCalories: replacing ? null : primary.targetCalories,
      intensityModel: replacing || effort ? "rpe" : primary.intensityModel,
      intensityTarget: effort ? { min: effort.min, max: effort.max } : replacing ? {} : primary.intensityTarget,
      effortLabel: effort ? effective.subtitle : replacing ? effective.subtitle : primary.effortLabel,
      why: effective.guideLine, steps: effective.steps.map((s) => s.label),
      stimulus: replacing ? replacementStimulus : primary.stimulus,
      runWalk: replacing ? catalog?.category === "walk_run" : primary.runWalk,
      startLabel: effective.startLabel,
      catalogWorkout: catalog ?? primary.catalogWorkout, effectiveWorkout: effective,
      catalogVersion: catalog ? standaloneWorkoutCatalog.version : primary.catalogVersion,
      workoutEditId: id, workoutRevision: "", archetypeId: null, allowShortSession: true };
    if (planned) {
      if (skip) await tx.plannedWorkout.update({ where: { id: planned.id }, data: { status: "skipped" } });
      else {
        // Adaptation has already replaced the original execution content. Persist that
        // effective phase tree even for effort-only edits, keeping the original slot and audit.
        const materializeAdaptive = !replacing && isAdaptivePlannedPrescription(primary);
        const rewritePhases = replacing || materializeAdaptive;
        // A canonical plain edit preserves its original phase rows and unedited targets.
        const provenance = catalog ? { catalogWorkoutId: catalog.id, catalogVersion: standaloneWorkoutCatalog.version } : {};
        const originalPrescription = planned.prescription as Record<string, unknown>;
        let stepIndex = 0;
        const recipes = rewritePhases ? effective.steps.map((step) => ({ type: step.coachingTarget?.phase ?? "main", durationSeconds: step.durationSeconds }))
          : planned.blocks.map((block, index) => {
              const count = Math.max(1, block.steps.length);
              const duration = effective.steps.slice(stepIndex, stepIndex + count).reduce((sum, step) => sum + step.durationSeconds, 0);
              stepIndex += count;
              const original = Array.isArray(originalPrescription.blocks) ? originalPrescription.blocks[index] as Record<string, unknown> | undefined : undefined;
              return { ...original, type: original?.type ?? block.blockType, durationSeconds: duration };
            });
        await tx.plannedWorkout.update({ where: { id: planned.id }, data: {
          title: after.title, durationSeconds, distanceMeters: after.distanceMeters,
          ...(rewritePhases ? { targetCalories: after.targetCalories ?? null, modality: effective.sport, stimulus: after.stimulus,
            isKeyWorkout: ["threshold", "speed", "longEndurance"].includes(after.stimulus), intensityModel: after.intensityModel,
            intensityTarget: json(after.intensityTarget ?? {}) } : {}),
          ...(effort ? { intensityModel: "rpe", intensityTarget: json({ min: effort.min, max: effort.max }) } : {}),
          prescription: json({ ...originalPrescription, ...provenance, blocks: recipes, effectiveWorkout: effective, workoutEditId: id }),
        } });
        if (rewritePhases) {
          await tx.workoutBlock.deleteMany({ where: { plannedWorkoutId: planned.id } });
          for (const [index, step] of effective.steps.entries()) await tx.workoutBlock.create({ data: {
            plannedWorkoutId: planned.id, sortOrder: index, blockType: step.coachingTarget?.phase ?? "main", modality: effective.sport,
            stimulus: after.stimulus, durationSeconds: step.durationSeconds,
            steps: { create: { sortOrder: 0, label: step.label, kind: step.coachingTarget?.phase ?? "easy", durationSeconds: step.durationSeconds,
              detail: step.detail, target: json({ ...step.coachingTarget,
                ...(materializeAdaptive ? { rpe: [effective.guideInstructions.segments[index].effort.rpeMin,
                  effective.guideInstructions.segments[index].effort.rpeMax] } : {}) }) } },
          } });
        } else if (edits?.target || effort) {
          let index = 0;
          for (const block of planned.blocks) {
            const sourceSteps = block.steps.length ? block.steps : [null];
            let blockDuration = 0;
            for (const step of sourceSteps) {
              const effectiveStep = effective.steps[index++];
              blockDuration += effectiveStep.durationSeconds;
              if (step) await tx.workoutStep.update({ where: { id: step.id }, data: {
                ...(edits?.target ? { label: effectiveStep.label, durationSeconds: effectiveStep.durationSeconds, distanceMeters: effective.targetDistanceMeters ?? null } : {}),
                ...(effort && !["warmup", "cooldown"].includes(effectiveStep.coachingTarget?.phase ?? "easy") ? { label: effectiveStep.label, detail: effectiveStep.detail, target: json({ rpe: [effort.min, effort.max] }) } : {}),
              } });
            }
            if (edits?.target) await tx.workoutBlock.update({ where: { id: block.id }, data: { durationSeconds: blockDuration, distanceMeters: effective.targetDistanceMeters ?? null } });
          }
        }
      }
    }
    const baseline = await buildBaseActivitySuggestion(userId, "stable", now, tx);
    // Calculate against effective data and the now-current planned slot, excluding audit references.
    const resultRevision = skip ? hash({ base: input.baseRevision, skip: true, id }) : await revision(tx, userId, { ...baseline, primary: after });
    after.workoutRevision = resultRevision;
    await tx.workoutEdit.create({ data: {
      id, userId, validForDate: input.validForDate, plannedWorkoutId: planned?.id ?? null, suggestionId: input.suggestionId,
      operation: input.change.operation, reason: input.reason ?? null, idempotencyKey: input.idempotencyKey, requestHash,
      baseRevision: input.baseRevision, resultRevision, beforeWorkout: json({ suggestion: primary, structure: beforeStructure }),
      afterWorkout: json({ suggestion: skip ? null : after, effectiveWorkout: skip ? null : effective }),
      validationContext: json({ resultStructureHash: planned && !skip ? hash(await structure(tx, userId, after)) : null,
        fingerprint: skip ? restFingerprint(baseline) : suggestionFingerprint(baseline),
        readinessId: await latestReadinessId(tx, userId), planId: baseline.planContext?.planId ?? null, activity: baseline.activityWatermark }),
    } });
    return { receipt: { plannedWorkoutId: planned?.id ?? null, workoutEditId: id, revision: resultRevision },
      state: await assemblePlanningState(userId, "updated", tx), activitySuggestion: await canonicalWorkoutSuggestion(tx, userId, "stable", now) };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 30_000 });
}
