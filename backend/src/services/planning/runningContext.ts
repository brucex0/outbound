import { accountTimeZone, accountDateLabel } from "../accountCalendar.js";
import type { Prisma } from "@prisma/client";
import type { GeneratePlanInput } from "./generator.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { isRunningActivityType, withSessionEffort } from "./sessionEffort.js";
import { evaluateRunWalkProgramme, freshReadiness, parseRunWalkProgramme, type PrescribedRunningEvidence } from "./runWalkProgramme.js";
import { runningDoseBudget, shortRunningSessionsAllowed } from "./runningDosePolicy.js";
import type { ActivityForPlanning, PlannedWorkoutForState, ReadinessForPlanning } from "./types.js";

/** Called under the planning-user lock: no progression from a stale event/AI snapshot. */
export async function loadRunningPlanningContext(tx: Prisma.TransactionClient, input: {
  userId: string; planId: string; goal: GeneratePlanInput["goal"]; previousProgramme?: unknown;
  now: Date; createdAt: Date; enableProgramme: boolean; authored?: boolean; authoredInitialSeconds?: number;
}) {
  const { userId, now } = input;
  const calendarDate = accountDateLabel(now, await accountTimeZone(userId, undefined, tx));
  const [rawActivities, planned, evidence, readiness, feedback] = await Promise.all([
    tx.activity.findMany({ where: { userId, deletedAt: null, startedAt: { gte: new Date(now.getTime() - 90 * 86400000), lte: now } },
      orderBy: { startedAt: "desc" }, take: 1000,
      select: { id: true, type: true, startedAt: true, durationSecs: true, distanceM: true, avgPace: true, avgHeartRate: true } }),
    tx.plannedWorkout.findMany({ where: { userId, scheduledDate: { gte: new Date(now.getTime() - 35 * 86400000) }, status: { in: ["completed", "skipped"] } },
      select: { id: true, scheduledDate: true, modality: true, stimulus: true, durationSeconds: true, distanceMeters: true, targetCalories: true, isKeyWorkout: true, status: true, prescription: true } }),
    tx.plannedWorkout.findMany({ where: { userId, modality: "run", status: "completed", planVersion: { planId: input.planId },
      scheduledDate: { gte: new Date(now.getTime() - 90 * 86400000) } },
      include: { blocks: { orderBy: { sortOrder: "asc" }, include: { steps: { orderBy: { sortOrder: "asc" } } } },
        completions: { select: { completedAt: true, durationSeconds: true, completionQuality: true, perceivedEffort: true, performedAsIssued: true, prescriptionRevision: { select: { programmeExposureEligible: true, sourceExposureEligible: true, stimulus: true } } } }, edits: { select: { operation: true } } } }),
    tx.readinessCheckIn.findMany({ where: { userId, date: { gte: new Date(now.getTime() - 2 * 86400000), lte: now } }, orderBy: { date: "desc" },
      select: { date: true, energy: true, soreness: true, stress: true, sleepQuality: true, motivation: true, illnessOrPain: true } }),
    tx.workoutFeedback.findMany({ where: { userId, recordedAt: { gte: new Date(now.getTime() - 7 * 86400000), lte: now } },
      select: { effort: true, recordedAt: true } }),
  ]);
  const activities = await withSessionEffort(tx, userId, rawActivities as ActivityForPlanning[]);
  const latestReadiness = freshReadiness(readiness as ReadinessForPlanning[], now);
  const athleteState = computeAthleteTrainingState({ activities, plannedWorkouts: planned as PlannedWorkoutForState[], readiness: latestReadiness ? [latestReadiness] : [], now });
  const previous = parseRunWalkProgramme(input.previousProgramme);
  const budget = runningDoseBudget(input.goal, athleteState, previous, input.authored);
  const runCount = budget?.sessionsPerWeek ?? input.goal.daysPerWeekTarget;
  const initialSeconds = Math.min(input.authoredInitialSeconds ?? Infinity, input.goal.maxSessionMinutes * 60,
    Math.max(shortRunningSessionsAllowed(input.goal) ? 600 : input.authored ? 0 : 1500, Math.min(1500, Math.floor(75 / Math.max(1, runCount)) * 60)));
  const cap = Math.min(input.goal.maxSessionMinutes * 60, previous?.status === "active" ? (budget?.ordinarySessionMinutes ?? initialSeconds / 60) * 60 : Infinity);
  const lastRecordedRunAt = activities.find((row) => isRunningActivityType(row.type) && ((row.durationSecs ?? 0) >= 300 || (row.distanceM ?? 0) >= 500))?.startedAt;
  const after = previous?.stageStartedOn ? new Date(previous.stageStartedOn) : input.createdAt;
  const evaluation = evaluateRunWalkProgramme({ calendarDate, previous, enabled: input.enableProgramme, now, createdAt: input.createdAt,
    evidence: evidence as PrescribedRunningEvidence[], athleteState, readiness: latestReadiness,
    explicitDifficulty: feedback.some((row) => row.recordedAt >= after && row.effort === "tooHard"), lastRecordedRunAt,
    initialSessionSeconds: initialSeconds, sessionCapSeconds: cap });
  return { ...evaluation, athleteState, activities, planned, evidence: evidence as PrescribedRunningEvidence[], latestReadiness };
}
