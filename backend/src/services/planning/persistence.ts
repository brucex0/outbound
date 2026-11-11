import { accountDateLabel, accountTimeZone } from "../accountCalendar.js";
import { Prisma, type TrainingPlanVersion } from "@prisma/client";
import type { PlannedWorkoutDraft } from "./types.js";

export async function createPlanVersionWithWorkouts(
  tx: Prisma.TransactionClient,
  input: {
    planId: string;
    userId: string;
    versionNumber: number;
    reason: string;
    effectiveFrom?: Date;
    summary: string;
    engineInputs?: Record<string, unknown>;
    engineDecision?: Record<string, unknown>;
    workouts: PlannedWorkoutDraft[];
  }
): Promise<TrainingPlanVersion> {
  // All callers hold the same user lock. Preserve completion IDs and history;
  // retire only future prescriptions, and never prescribe another required run
  // on a date already completed/skipped in any version of this plan.
  const effectiveFrom = input.effectiveFrom ?? new Date();
  const today = accountDateLabel(effectiveFrom, await accountTimeZone(input.userId, undefined, tx));
  const protectedWorkouts = await tx.plannedWorkout.findMany({
    where: { userId: input.userId, planVersion: { planId: input.planId }, status: { in: ["completed", "skipped"] } },
    select: { scheduledDate: true, prescription: true },
  });
  const edited = await tx.plannedWorkout.findMany({
    where: { userId: input.userId, planVersion: { planId: input.planId }, status: "planned", scheduledDate: { gte: today },
      OR: [{ edits: { some: { operation: { not: "skip" } } } }, { prescription: { path: ["source"], equals: "explicitWorkoutChange" } }] },
    select: { id: true, scheduledDate: true, prescription: true },
  });
  const protectedDays = new Set([...protectedWorkouts, ...edited].map(workoutSlotKey));
  await tx.plannedWorkout.updateMany({
    where: { userId: input.userId, planVersion: { planId: input.planId }, status: "planned", scheduledDate: { gte: today }, id: { notIn: edited.map((row) => row.id) } },
    data: { status: "superseded" },
  });
  const version = await tx.trainingPlanVersion.create({
    data: {
      planId: input.planId,
      versionNumber: input.versionNumber,
      reason: input.reason,
      effectiveFrom: input.effectiveFrom ?? new Date(),
      summary: input.summary,
      engineInputs: json(input.engineInputs ?? {}),
      engineDecision: json(input.engineDecision ?? {}),
    },
  });

  for (const workout of input.workouts) {
    if (protectedDays.has(workoutSlotKey(workout))) continue;
    await tx.plannedWorkout.create({
      data: {
        planVersionId: version.id,
        userId: input.userId,
        scheduledDate: workout.scheduledDate,
        modality: workout.modality,
        stimulus: workout.stimulus,
        title: workout.title,
        durationSeconds: workout.durationSeconds,
        distanceMeters: workout.distanceMeters ?? null,
        targetCalories: workout.targetCalories ?? null,
        intensityModel: workout.intensityModel,
        intensityTarget: workout.intensityTarget ? json(workout.intensityTarget) : Prisma.JsonNull,
        prescription: json(workout.prescription),
        isKeyWorkout: workout.isKeyWorkout,
        blocks: {
          create: workout.blocks.map((block, blockIndex) => ({
            sortOrder: blockIndex,
            blockType: block.blockType,
            modality: block.modality,
            stimulus: block.stimulus,
            durationSeconds: block.durationSeconds ?? null,
            distanceMeters: block.distanceMeters ?? null,
            repeats: block.repeats ?? null,
            restSeconds: block.restSeconds ?? null,
            metadata: json(block.metadata ?? {}),
            steps: {
              create: block.steps.map((step, stepIndex) => ({
                sortOrder: stepIndex,
                label: step.label,
                kind: step.kind,
                durationSeconds: step.durationSeconds ?? null,
                distanceMeters: step.distanceMeters ?? null,
                target: step.target ? json(step.target) : Prisma.JsonNull,
                detail: step.detail ?? null,
              })),
            },
          })),
        },
      },
    });
  }

  return version;
}

export function json(value: Record<string, unknown>): Prisma.InputJsonValue {
  return value as Prisma.InputJsonValue;
}

/** Serialize planning changes with goal replacement, completion and refill. */
export async function lockPlanningUser(tx: Prisma.TransactionClient, userId: string): Promise<void> {
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${userId}))`;
}

export function isOptionalWorkout(workout: { prescription: unknown }): boolean {
  const prescription = workout.prescription;
  return typeof prescription === "object" && prescription !== null && !Array.isArray(prescription)
    && (prescription as Record<string, unknown>).optional === true;
}
export function workoutSlotKey(workout: { scheduledDate: Date; prescription: unknown }): string {
  return `${workout.scheduledDate.toISOString().slice(0, 10)}:${isOptionalWorkout(workout) ? "optional" : "required"}`;
}

/** Still-active explicit edits retain their original version, IDs and phase rows. */
export async function protectedEditedWorkouts(tx: Prisma.TransactionClient, userId: string, planId: string, versionId: string, since: Date) {
  return tx.plannedWorkout.findMany({
    where: { userId, planVersion: { planId }, planVersionId: { not: versionId }, status: "planned", scheduledDate: { gte: since },
      OR: [{ edits: { some: { operation: { not: "skip" } } } }, { prescription: { path: ["source"], equals: "explicitWorkoutChange" } }] },
    orderBy: { scheduledDate: "asc" },
    include: { blocks: { orderBy: { sortOrder: "asc" }, include: { steps: { orderBy: { sortOrder: "asc" } } } } },
  });
}
