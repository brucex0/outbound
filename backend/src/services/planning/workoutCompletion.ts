import { Prisma } from "@prisma/client";
import { isOptionalWorkout } from "./persistence.js";
import { isRunningActivityType, reportedEffort } from "./sessionEffort.js";
import { PerformedWorkoutConflictError, validatePerformedReference } from "./workoutIssuance.js";
import type { CompleteWorkoutInput } from "./types.js";

type Activity = Prisma.ActivityGetPayload<{}>;
/** Caller holds the user planning lock. Completion and its activity are one commit. */
export async function recordWorkoutCompletion(tx: Prisma.TransactionClient, userId: string, workoutId: string,
  input: CompleteWorkoutInput, performedReference?: unknown) {
  const workout = await tx.plannedWorkout.findFirst({ where: { id: workoutId, userId }, include: { planVersion: true } });
  if (!workout) throw new PerformedWorkoutConflictError("unavailable_reference");
  const issued = performedReference != null ? await validatePerformedReference(tx, userId, performedReference) : null;
  if (issued && issued.plannedWorkoutId !== workout.id) throw new PerformedWorkoutConflictError("unavailable_reference");
  if (issued && (input.workoutEditId !== undefined && input.workoutEditId !== issued.workoutEditId
      || input.workoutRevision !== undefined && input.workoutRevision !== issued.workoutRevision)) throw new PerformedWorkoutConflictError("edit_reference");
  // A retained receipt's null edit linkage is authoritative too.
  const editId = issued ? issued.workoutEditId : input.workoutEditId ?? null;
  const editRevision = issued ? issued.workoutRevision : input.workoutRevision ?? null;
  if (Boolean(editId) !== Boolean(editRevision)) throw new PerformedWorkoutConflictError("edit_reference");
  if (editId && !await tx.workoutEdit.findFirst({ where: { id: editId, userId, plannedWorkoutId: workout.id,
    resultRevision: editRevision!, operation: { not: "skip" } }, select: { id: true } })) throw new PerformedWorkoutConflictError("edit_reference");
  const activity = input.activityId ? await tx.activity.findFirst({ where: { id: input.activityId, userId, deletedAt: null } }) : null;
  if (input.activityId && !activity) throw new PerformedWorkoutConflictError("unavailable_reference");
  const performedAsIssued = issued ? (performedReference as { performedAsIssued: boolean }).performedAsIssued
    && (!activity || activityMatches(activity.type, (issued.snapshot as Record<string, unknown>).modality)) : null;
  const associated = activity ? await tx.workoutCompletion.findUnique({ where: { activityId: activity.id } }) : null;
  if (associated && (associated.userId !== userId || associated.plannedWorkoutId !== workout.id
      || associated.prescriptionRevisionId && associated.prescriptionRevisionId !== issued?.id
      || associated.performedAsIssued !== performedAsIssued
      || (associated.workoutEditId ?? null) !== editId || (associated.workoutRevision ?? null) !== editRevision)) {
    throw new PerformedWorkoutConflictError("reassigned_activity");
  }
  if (!activity && workout.status === "completed") return { changed: false, workout };
  const canonical = activity ? completionFromActivity(activity) : {};
  const values = {
    plannedWorkoutId: workout.id, userId, activityId: activity?.id ?? null,
    workoutEditId: editId, workoutRevision: editRevision, performedAsIssued, prescriptionRevisionId: issued?.id ?? associated?.prescriptionRevisionId ?? null,
    completedAt: input.completedAt ? new Date(input.completedAt) : new Date(), durationSeconds: input.durationSeconds ?? null,
    distanceMeters: input.distanceMeters ?? null, targetCalories: issued
      ? typeof (issued.snapshot as Record<string, unknown>).targetCalories === "number" ? (issued.snapshot as Record<string, unknown>).targetCalories as number : null
      : input.targetCalories ?? workout.targetCalories ?? null,
    energyKilocalories: input.energyKilocalories ?? null, avgPace: input.avgPace ?? null, avgHeartRate: input.avgHeartRate ?? null,
    avgPower: input.avgPower ?? null, perceivedEffort: input.perceivedEffort ?? null, notes: input.notes ?? null,
    ...canonical,
  };
  let changed = false;
  if (associated) {
    await tx.workoutCompletion.update({ where: { id: associated.id }, data: { ...values,
      ...(associated.completionQuality === "completed" && input.completionQuality ? { completionQuality: input.completionQuality } : {}) } });
  } else {
    // A reference alone cannot identify an earlier unlinked physical recording.
    // Preserve those manual/best-effort records; canonical uploads get their own receipt.
    await tx.workoutCompletion.create({ data: { ...values, completionQuality: input.completionQuality ?? "completed" } });
    changed = true;
  }
  if (workout.status !== "completed") {
    await tx.plannedWorkout.update({ where: { id: workout.id }, data: { status: "completed" } });
    // Old/inactive-plan receipts never supersede another plan's current slot.
    const replacements = await tx.plannedWorkout.findMany({ where: { userId, id: { not: workout.id },
      planVersion: { planId: workout.planVersion.planId }, scheduledDate: workout.scheduledDate, status: "planned" }, select: { id: true, prescription: true } });
    await tx.plannedWorkout.updateMany({ where: { id: { in: replacements.filter((row) => isOptionalWorkout(row) === isOptionalWorkout(workout)).map((row) => row.id) } }, data: { status: "superseded" } });
  }
  return { changed, workout };
}

/** Every create/update/recording-dedup path calls this before the transaction commits. */
export async function reconcileUploadedWorkout(tx: Prisma.TransactionClient, userId: string, activity: Activity, referenceValue: unknown) {
  const existing = await tx.workoutCompletion.findUnique({ where: { activityId: activity.id }, include: { prescriptionRevision: true } });
  if (referenceValue == null) {
    // Missing optional metadata never clears an already-owned canonical association.
    if (!existing?.prescriptionRevision) return;
    const row = await tx.plannedWorkout.findUniqueOrThrow({ where: { id: existing.plannedWorkoutId } });
    referenceValue = { policyVersion: "performed-workout-v1", performedAsIssued: existing.performedAsIssued === true, issuanceId: existing.prescriptionRevision.id,
      revision: existing.prescriptionRevision.revision, plannedWorkoutId: row.id, planVersionId: row.planVersionId,
      workoutEditId: existing.prescriptionRevision.workoutEditId, workoutRevision: existing.prescriptionRevision.workoutRevision };
  }
  const issued = await validatePerformedReference(tx, userId, referenceValue);
  const privateData = object(activity.clientData);
  const quality = ["completed", "feltEasy", "tooHard", "cutShort", "notCompleted"].includes(String(privateData.plannedWorkoutCompletionQuality))
    ? String(privateData.plannedWorkoutCompletionQuality) : "completed";
  const result = await recordWorkoutCompletion(tx, userId, issued.plannedWorkoutId, { activityId: activity.id, completionQuality: quality }, referenceValue);
  const normalizedReference = { ...(referenceValue as Record<string, unknown>), performedAsIssued: (referenceValue as { performedAsIssued: boolean }).performedAsIssued
    && activityMatches(activity.type, (issued.snapshot as Record<string, unknown>).modality) };
  await tx.activity.update({ where: { id: activity.id }, data: { clientData: JSON.parse(JSON.stringify({ ...privateData, performedWorkoutReference: normalizedReference })) } });
  console.info("[planning] performed_workout_reconciled", { result: result.changed ? "recorded" : "replayed",
    recipeUse: normalizedReference.performedAsIssued ? "as_issued" : "local_variant",
    progression: !normalizedReference.performedAsIssued ? "none" : issued.sourceExposureEligible ? "source_and_programme" : issued.programmeExposureEligible ? "programme_only" : "none" });
  return { changed: result.changed, planId: result.workout.planVersion.planId };
}
function completionFromActivity(activity: Activity) {
  const endedAt = activity.endedAt ?? new Date(activity.startedAt.getTime() + (activity.durationSecs ?? 0) * 1000);
  return { completedAt: endedAt, durationSeconds: activity.durationSecs, distanceMeters: activity.distanceM,
    energyKilocalories: activity.energyKilocalories, avgPace: activity.avgPace, avgHeartRate: activity.avgHeartRate,
    perceivedEffort: reportedEffort(object(activity.clientData).sessionEffortRating) };
}
function object(value: unknown): Record<string, unknown> { return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

function activityMatches(type: string, modality: unknown): boolean {
  if (modality === "run") return isRunningActivityType(type);
  if (modality === "bike") return /cycl|bike/i.test(type);
  if (modality === "walk") return /walk|hik/i.test(type);
  return type.toLowerCase() === modality;
}
