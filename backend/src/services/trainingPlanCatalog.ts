import {
  fallbackTrainingPlanCatalog,
  makeTrainingPlanCatalog,
  type TrainingPlanCatalog,
  type TrainingPlanSource,
  type TrainingPlanTemplate,
} from "./trainingPlans.js";
import { getPrismaClient } from "./prisma.js";

export async function loadTrainingPlanCatalog(): Promise<TrainingPlanCatalog> {
  const records = await getPrismaClient().trainingPlanTemplate.findMany({
    orderBy: [{ focus: "asc" }, { title: "asc" }],
    include: {
      weeks: {
        orderBy: { weekIndex: "asc" },
        include: {
          workouts: {
            orderBy: { sortOrder: "asc" },
            include: {
              steps: {
                orderBy: { sortOrder: "asc" },
              },
            },
          },
        },
      },
    },
  });

  if (records.length === 0) {
    return fallbackTrainingPlanCatalog;
  }

  return makeTrainingPlanCatalog(
    records.map((record): TrainingPlanTemplate => ({
      id: record.id,
      focus: record.focus as TrainingPlanTemplate["focus"],
      sport: record.sport as TrainingPlanTemplate["sport"],
      title: record.title,
      subtitle: record.subtitle,
      defaultWeeks: record.defaultWeeks,
      minSessionsPerWeek: record.minSessionsPerWeek,
      maxSessionsPerWeek: record.maxSessionsPerWeek,
      baseWeeklyMinutes: record.baseWeeklyMinutes,
      baseLongSessionMinutes: record.baseLongSessionMinutes,
      summary: record.summary,
      highlights: record.highlights,
      source: record.source ? (record.source as unknown as TrainingPlanSource) : null,
      weeks: record.weeks.map((week) => ({
        id: week.sourceId,
        index: week.weekIndex,
        focus: week.focus,
        summary: week.summary,
        notes: week.notes,
        workouts: week.workouts.map((workout) => ({
          id: workout.sourceId,
          title: workout.title,
          kind: workout.kind as TrainingPlanTemplate["weeks"][number]["workouts"][number]["kind"],
          dayLabel: workout.dayLabel,
          summary: workout.summary,
          purpose: workout.purpose,
          coachCue: workout.coachCue,
          effortLabel: workout.effortLabel,
          durationSeconds: workout.durationSeconds,
          distanceLabel: workout.distanceLabel,
          isOptional: workout.isOptional,
          steps: workout.steps.map((step) => ({
            id: step.sourceId,
            kind: step.kind as TrainingPlanTemplate["weeks"][number]["workouts"][number]["steps"][number]["kind"],
            label: step.label,
            durationSeconds: step.durationSeconds,
            detail: step.detail,
          })),
        })),
      })),
    }))
  );
}
