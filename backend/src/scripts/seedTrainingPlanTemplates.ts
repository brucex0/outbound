import { Prisma, PrismaClient } from "@prisma/client";
import { trainingPlanTemplates } from "../data/trainingPlanTemplates.js";
import type { TrainingPlanTemplate } from "../services/trainingPlans.js";

const prisma = new PrismaClient();
const templates = trainingPlanTemplates as unknown as TrainingPlanTemplate[];

export async function seedTrainingPlanTemplates(client: PrismaClient = prisma) {
  await client.$transaction(
    async (tx) => {
      await tx.trainingPlanTemplate.deleteMany({});

      for (const template of templates) {
        await tx.trainingPlanTemplate.create({
          data: {
            id: template.id,
            focus: template.focus,
            sport: template.sport,
            title: template.title,
            subtitle: template.subtitle,
            defaultWeeks: template.defaultWeeks,
            minSessionsPerWeek: template.minSessionsPerWeek,
            maxSessionsPerWeek: template.maxSessionsPerWeek,
            baseWeeklyMinutes: template.baseWeeklyMinutes,
            baseLongSessionMinutes: template.baseLongSessionMinutes,
            summary: template.summary,
            highlights: template.highlights,
            source: template.source
              ? (template.source as unknown as Prisma.InputJsonValue)
              : Prisma.JsonNull,
            weeks: {
              create: template.weeks.map((week) => ({
                sourceId: week.id,
                weekIndex: week.index,
                focus: week.focus,
                summary: week.summary,
                notes: week.notes,
                workouts: {
                  create: week.workouts.map((workout, workoutIndex) => ({
                    sourceId: workout.id,
                    sortOrder: workoutIndex,
                    title: workout.title,
                    kind: workout.kind,
                    dayLabel: workout.dayLabel,
                    summary: workout.summary,
                    purpose: workout.purpose,
                    coachCue: workout.coachCue,
                    effortLabel: workout.effortLabel,
                    durationSeconds: workout.durationSeconds,
                    distanceLabel: workout.distanceLabel ?? null,
                    isOptional: workout.isOptional,
                    steps: {
                      create: workout.steps.map((step, stepIndex) => ({
                        sourceId: step.id,
                        sortOrder: stepIndex,
                        kind: step.kind,
                        label: step.label,
                        durationSeconds: step.durationSeconds,
                        detail: step.detail ?? null,
                      })),
                    },
                  })),
                },
              })),
            },
          },
        });
      }
    },
    { timeout: 60_000 }
  );

  return { templateCount: templates.length };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const result = await seedTrainingPlanTemplates();
    console.log(`[seed] Seeded ${result.templateCount} training plan templates.`);
  } finally {
    await prisma.$disconnect();
  }
}
