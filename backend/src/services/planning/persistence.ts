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
