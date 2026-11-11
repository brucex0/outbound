import { createHash } from "node:crypto";
import { Prisma, type PrismaClient, type WorkoutPrescriptionRevision } from "@prisma/client";
import { z } from "zod";
import type { StandaloneWorkoutCatalogItem } from "../../data/standaloneWorkouts.js";
import { storedEffectiveWorkout } from "./workoutEdits.js";
import { runningDoseSignature } from "./runWalkProgramme.js";
import type { ActivitySuggestion } from "./types.js";

export const PERFORMED_WORKOUT_POLICY = "performed-workout-v1";
export const performedWorkoutReferenceSchema = z.object({
  policyVersion: z.literal(PERFORMED_WORKOUT_POLICY), issuanceId: z.string().min(1).max(160),
  performedAsIssued: z.boolean(),
  revision: z.string().regex(/^[a-f0-9]{64}$/), plannedWorkoutId: z.string().min(1).max(160), planVersionId: z.string().min(1).max(160),
  workoutEditId: z.string().min(1).max(160).nullish(), workoutRevision: z.string().regex(/^[a-f0-9]{64}$/).nullish(),
}).strict();
export type PerformedWorkoutReference = z.infer<typeof performedWorkoutReferenceSchema>;
export class PerformedWorkoutConflictError extends Error {
  readonly code = "performed_workout_conflict";
  constructor(readonly category: "invalid_reference" | "unavailable_reference" | "reassigned_activity" | "edit_reference") {
    super("The saved activity's issued workout reference is unavailable. Keep the saved activity and retry synchronization after refreshing planning data.");
  }
}

/** Same user lock as edits/refill; a transaction caller retains its existing transaction. */
export async function withIssuanceTransaction<T>(db: Prisma.TransactionClient, userId: string, work: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
  if (typeof (db as Partial<PrismaClient>).$transaction === "function") return (db as PrismaClient).$transaction(async (tx) => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${userId}))`;
    return work(tx);
  }, { timeout: 30_000 });
  await db.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${userId}))`;
  return work(db);
}
const include = { blocks: { orderBy: { sortOrder: "asc" as const }, include: { steps: { orderBy: { sortOrder: "asc" as const } } } }, edits: { select: { operation: true } } };

/** Register the exact response being issued now; never reconstruct an old client recipe. */
export async function issueWorkout(tx: Prisma.TransactionClient, userId: string, workoutId: string,
  actual?: { primary: ActivitySuggestion; effective: StandaloneWorkoutCatalogItem; replacement?: boolean }): Promise<PerformedWorkoutReference | null> {
  const row = await tx.plannedWorkout.findFirst({ where: { id: workoutId, userId, status: "planned" }, include });
  if (!row) return null;
  const prescription = row.prescription as Record<string, unknown>;
  const target = row.intensityTarget as Record<string, unknown> | null;
  const rawPrimary: ActivitySuggestion = {
    id: `planned-${row.id}`, title: row.title, modality: row.modality as ActivitySuggestion["modality"], stimulus: row.stimulus as ActivitySuggestion["stimulus"],
    durationMinutes: Math.ceil(row.durationSeconds / 60), durationSeconds: row.durationSeconds, distanceMeters: row.distanceMeters, targetCalories: row.targetCalories,
    effortLabel: typeof target?.effortLabel === "string" ? target.effortLabel : "Easy", intensityModel: (["pace", "heartRate", "power", "open"].includes(row.intensityModel) ? row.intensityModel : "rpe") as ActivitySuggestion["intensityModel"],
    intensityTarget: target, why: typeof prescription.guideCue === "string" ? prescription.guideCue : row.title,
    steps: row.blocks.flatMap((block) => block.steps.map((step) => step.label)), startLabel: "Start", plannedWorkoutId: row.id,
    optional: prescription.optional === true, runWalk: prescription.runWalk === true,
  };
  // Persisted direct edits own their actual effective phase snapshot.
  const rawEffective = await storedEffectiveWorkout(tx, userId, rawPrimary);
  const primary = actual?.primary ?? rawPrimary, effective = actual?.effective ?? rawEffective;
  const editId = primary.workoutEditId ?? (typeof prescription.workoutEditId === "string" ? prescription.workoutEditId : null);
  let edit = editId ? await tx.workoutEdit.findFirst({ where: { id: editId, userId, plannedWorkoutId: row.id, operation: { not: "skip" } }, select: { id: true, resultRevision: true, afterWorkout: true } }) : null;
  const edited = edit?.afterWorkout as unknown as { suggestion?: ActivitySuggestion; effectiveWorkout?: StandaloneWorkoutCatalogItem };
  if (!edited?.suggestion || !edited.effectiveWorkout || hash(execution(edited.suggestion, edited.effectiveWorkout)) !== hash(execution(primary, effective))
      || hash(edited.effectiveWorkout) !== hash(effective)) edit = null;
  if (primary.workoutEditId && !edit || primary.workoutRevision && primary.workoutRevision !== edit?.resultRevision) throw new PerformedWorkoutConflictError("edit_reference");
  const issued = prescription.issuedRunningDose as { signature?: string } | undefined;
  const unchangedProgramme = row.modality === "run" && !edit && prescription.source !== "explicitWorkoutChange"
    && !row.edits.some((value) => value.operation !== "skip")
    && issued?.signature === runningDoseSignature(row);
  const sameExecution = hash(execution(rawPrimary, rawEffective)) === hash(execution(primary, effective));
  const programmeExposureEligible = unchangedProgramme && sameExecution && !actual?.replacement;
  const sourceExposureEligible = programmeExposureEligible && prescription.sourceExposureEligible !== false;
  const snapshot = { policyVersion: PERFORMED_WORKOUT_POLICY, modality: primary.modality, stimulus: primary.stimulus,
    targetCalories: primary.targetCalories ?? null, effectiveWorkout: effective,
    provenance: { source: prescription.source ?? null, templateID: prescription.templateID ?? null, weekIndex: prescription.weekIndex ?? null,
      workoutID: prescription.workoutID ?? null, runWalkProgramme: prescription.runWalkProgramme ?? null,
      issuedDoseSignature: issued?.signature ?? null, programmeExposureEligible, sourceExposureEligible, effectiveReplacement: actual?.replacement === true } };
  const revision = hash({ snapshot, workoutEditId: edit?.id ?? null, workoutRevision: edit?.resultRevision ?? null });
  const saved = await tx.workoutPrescriptionRevision.upsert({ where: { plannedWorkoutId_revision: { plannedWorkoutId: row.id, revision } },
    create: { plannedWorkoutId: row.id, revision, snapshot: JSON.parse(JSON.stringify(snapshot)), stimulus: primary.stimulus,
      programmeExposureEligible, sourceExposureEligible, workoutEditId: edit?.id ?? null, workoutRevision: edit?.resultRevision ?? null }, update: {} });
  return reference(saved, row.planVersionId);
}

export async function validatePerformedReference(tx: Prisma.TransactionClient, userId: string, value: unknown) {
  const parsed = performedWorkoutReferenceSchema.safeParse(value);
  if (!parsed.success || Boolean(parsed.data.workoutEditId) !== Boolean(parsed.data.workoutRevision)) throw new PerformedWorkoutConflictError("invalid_reference");
  const ref = parsed.data;
  const issued = await tx.workoutPrescriptionRevision.findFirst({ where: { id: ref.issuanceId, revision: ref.revision,
    plannedWorkoutId: ref.plannedWorkoutId, plannedWorkout: { userId, planVersionId: ref.planVersionId } }, include: { plannedWorkout: { include: { planVersion: true } } } });
  if (!issued) throw new PerformedWorkoutConflictError("unavailable_reference");
  if ((ref.workoutEditId ?? null) !== issued.workoutEditId || (ref.workoutRevision ?? null) !== issued.workoutRevision) throw new PerformedWorkoutConflictError("edit_reference");
  if (issued.workoutEditId && !await tx.workoutEdit.findFirst({ where: { id: issued.workoutEditId, userId, plannedWorkoutId: issued.plannedWorkoutId,
    resultRevision: issued.workoutRevision!, operation: { not: "skip" } }, select: { id: true } })) throw new PerformedWorkoutConflictError("edit_reference");
  return issued;
}
function reference(issued: WorkoutPrescriptionRevision, planVersionId: string): PerformedWorkoutReference {
  return { policyVersion: PERFORMED_WORKOUT_POLICY, performedAsIssued: true, issuanceId: issued.id, revision: issued.revision,
    plannedWorkoutId: issued.plannedWorkoutId, planVersionId, workoutEditId: issued.workoutEditId, workoutRevision: issued.workoutRevision };
}
function execution(primary: ActivitySuggestion, effective: StandaloneWorkoutCatalogItem) {
  return { modality: primary.modality, stimulus: primary.stimulus, durationSeconds: primary.durationSeconds ?? primary.durationMinutes * 60,
    distanceMeters: primary.distanceMeters ?? null, targetCalories: primary.targetCalories ?? null, intensityModel: primary.intensityModel,
    steps: effective.steps.map((step, index) => ({ durationSeconds: step.durationSeconds, target: step.coachingTarget ?? null,
      rpeMin: effective.guideInstructions.segments[index]?.effort.rpeMin, rpeMax: effective.guideInstructions.segments[index]?.effort.rpeMax })) };
}
function hash(value: unknown) { return createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex"); }
function canonical(value: any): any { return Array.isArray(value) ? value.map(canonical) : value != null && typeof value === "object"
  ? Object.fromEntries(Object.keys(value).filter((key) => value[key] !== undefined).sort().map((key) => [key, canonical(value[key])])) : value; }
