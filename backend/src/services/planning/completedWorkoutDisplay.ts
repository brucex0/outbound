import { z } from "zod";
import { mondayDateLabel } from "../accountCalendar.js";
import { fallbackTrainingPlanCatalog } from "../trainingPlans.js";
import type { Prisma } from "@prisma/client";
import type { PlannedWorkoutDraft } from "./types.js";

/** Private presentation only; never used to authorize completion or progression. */
export const completedWorkoutDisplaySchema = z.object({
  workoutTitle: z.string().min(1).max(500),
  planTitleKey: z.string().regex(/^training_plan\.title\.[a-z0-9_]+$/).max(160),
  dayNumber: z.number().int().positive().max(100),
  weekNumber: z.number().int().positive().max(10000),
}).strict();

export async function completedWorkoutDisplay(tx: Prisma.TransactionClient, workout: { title: string; prescription: unknown }) {
  const prescription = record(workout.prescription);
  // Catalog fillers can retain a borrowed workoutID; it is not their own
  // authored day. Optional support work likewise has no required-slot ordinal.
  if (prescription.filler === true || prescription.optional === true) return null;
  if (prescription.source !== "trainingPlanCatalog") {
    const retained = completedWorkoutDisplaySchema.safeParse({ ...record(prescription.completionDisplay), workoutTitle: workout.title });
    if (retained.success) return retained.data;
  }
  // Resolve the complete authored sequence, including sessions omitted by a
  // reduced frequency or a midweek start. Never enumerate the rolling response.
  if (typeof prescription.templateID !== "string" || typeof prescription.workoutID !== "string"
      || !Number.isInteger(prescription.weekIndex)) return null;
  const stored = await tx.trainingPlanTemplate.findUnique({ where: { id: prescription.templateID }, select: {
    titleKey: true, weeks: { where: { weekIndex: prescription.weekIndex as number }, select: {
      workouts: { where: { isOptional: false, durationSeconds: { gt: 0 } }, orderBy: { sortOrder: "asc" }, select: { sourceId: true } },
    } },
  } });
  const fallback = fallbackTrainingPlanCatalog.templateLookup.get(prescription.templateID);
  const planTitleKey = stored?.titleKey ?? fallback?.titleKey;
  const sequence = stored ? stored.weeks[0]?.workouts.map((row) => row.sourceId)
    : fallback?.weeks.find((row) => row.index === prescription.weekIndex)?.workouts
      .filter((row) => !row.isOptional && row.durationSeconds > 0).map((row) => row.id);
  const index = sequence?.indexOf(prescription.workoutID) ?? -1;
  if (!planTitleKey || index < 0) return null;
  const display = completedWorkoutDisplaySchema.safeParse({ workoutTitle: workout.title, planTitleKey,
    dayNumber: index + 1, weekNumber: prescription.weekIndex });
  return display.success ? display.data : null;
}

/** Stamp before past dates are removed; future refills retain the original slot number. */
export function retainGeneratedWorkoutDisplay(workouts: PlannedWorkoutDraft[], planStart: Date | undefined,
  goal: { type: string; targetDistanceMeters?: number | null }): PlannedWorkoutDraft[] {
  if (!planStart) return workouts;
  const planMonday = mondayDateLabel(planStart).getTime();
  const counters = new Map<number, number>();
  const planTitleKey = adaptivePlanTitleKey(goal);
  return workouts.map((workout) => {
    if (workout.prescription.optional === true) return workout;
    const monday = mondayDateLabel(workout.scheduledDate).getTime();
    const dayNumber = (counters.get(monday) ?? 0) + 1;
    counters.set(monday, dayNumber);
    const weekNumber = Math.max(1, Math.round((monday - planMonday) / 604800000) + 1);
    return { ...workout, prescription: { ...workout.prescription,
      completionDisplay: { planTitleKey, dayNumber, weekNumber } } };
  });
}

function adaptivePlanTitleKey(goal: { type: string; targetDistanceMeters?: number | null }): string {
  const type = goal.type.toLowerCase();
  const explicit: Record<string, string> = { consistency: "consistency", comeback: "comeback", fivek: "5k", tenk: "10k",
    tenmile: "10mile", halfmarathon: "half", marathon: "marathon" };
  const distance = goal.targetDistanceMeters ?? 0;
  const focus = explicit[type] ?? (distance >= 40000 ? "marathon" : distance >= 20000 ? "half" : distance >= 15000 ? "10mile"
    : distance >= 9000 ? "10k" : distance >= 4000 ? "5k" : type.includes("comeback") ? "comeback"
    : type.includes("marathon") && !type.includes("half") ? "marathon" : type.includes("half") ? "half"
    : type.includes("10k") ? "10k" : type.includes("5k") ? "5k" : "consistency");
  return `training_plan.title.adaptive_${focus}`;
}

function record(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
