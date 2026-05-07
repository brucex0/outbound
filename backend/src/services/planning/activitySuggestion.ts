import { computeAthleteTrainingState } from "./athleteState.js";
import { getPrismaClient } from "../prisma.js";
import type {
  ActivityForPlanning,
  ActivitySuggestion,
  ActivitySuggestionRelationship,
  ActivitySuggestionResponse,
  ActivitySuggestionSource,
  AthleteTrainingStateSnapshot,
  Modality,
  PlannedWorkoutForState,
  PlanningStatus,
  ReadinessForPlanning,
  TrainingStimulus,
} from "./types.js";
import type { Prisma } from "@prisma/client";

const ALGORITHM_VERSION = "activity-suggestion-v1";

type PlannedWorkoutWithBlocks = Prisma.PlannedWorkoutGetPayload<{
  include: {
    blocks: {
      orderBy: { sortOrder: "asc" };
      include: { steps: { orderBy: { sortOrder: "asc" } } };
    };
  };
}>;

type ActivePlanWithWorkouts = Prisma.TrainingPlanGetPayload<{
  include: {
    goal: true;
    versions: {
      orderBy: { versionNumber: "desc" };
      take: 1;
      include: {
        workouts: {
          orderBy: { scheduledDate: "asc" };
          include: {
            blocks: {
              orderBy: { sortOrder: "asc" };
              include: { steps: { orderBy: { sortOrder: "asc" } } };
            };
          };
        };
      };
    };
  };
}>;

export async function buildActivitySuggestion(
  userId: string,
  planningStatus: PlanningStatus = "stable",
  now: Date = new Date()
): Promise<ActivitySuggestionResponse> {
  const prisma = getPrismaClient();
  const todayStart = startOfDay(now);
  const tomorrowStart = addDays(todayStart, 1);
  const [plan, activities, readiness] = await Promise.all([
    prisma.trainingPlan.findFirst({
      where: { userId, status: "active" },
      orderBy: { createdAt: "desc" },
      include: {
        goal: true,
        versions: {
          orderBy: { versionNumber: "desc" },
          take: 1,
          include: {
            workouts: {
              orderBy: { scheduledDate: "asc" },
              include: {
                blocks: {
                  orderBy: { sortOrder: "asc" },
                  include: { steps: { orderBy: { sortOrder: "asc" } } },
                },
              },
            },
          },
        },
      },
    }),
    prisma.activity.findMany({
      where: { userId, startedAt: { gte: addDays(now, -28) } },
      orderBy: { startedAt: "desc" },
      select: {
        id: true,
        type: true,
        startedAt: true,
        durationSecs: true,
        distanceM: true,
        avgPace: true,
        avgHeartRate: true,
      },
    }),
    prisma.readinessCheckIn.findFirst({
      where: { userId },
      orderBy: { date: "desc" },
    }),
  ]);

  const typedActivities = activities as ActivityForPlanning[];
  const latestVersion = plan?.versions[0] ?? null;
  const workouts = latestVersion?.workouts ?? [];
  const plannedWorkouts = workouts.map(plannedWorkoutForState);
  const latestReadiness = readiness ? readinessForPlanning(readiness) : undefined;
  const athleteState = computeAthleteTrainingState({
    activities: typedActivities,
    plannedWorkouts,
    readiness: latestReadiness ? [latestReadiness] : [],
    now,
  });
  const todayActivities = typedActivities.filter(
    (activity) => activity.startedAt >= todayStart && activity.startedAt < tomorrowStart
  );
  const todayWorkout = workouts.find(
    (workout) =>
      sameDay(workout.scheduledDate, todayStart) &&
      !["completed", "skipped", "replaced"].includes(workout.status)
  );
  const upcomingWorkout =
    workouts.find((workout) => workout.scheduledDate >= todayStart && workout.status === "planned") ?? null;
  const base = baseResponse({
    now,
    planningStatus,
    planVersionId: latestVersion?.id ?? null,
    planContext: plan
      ? {
          planId: plan.id,
          planVersionId: latestVersion?.id ?? null,
          title: planTitleFromGoal(plan.goal.type),
        }
      : null,
    activities: typedActivities,
  });

  if (latestReadiness?.illnessOrPain) {
    return {
      ...base,
      status: "restRecommended",
      source: "recovery",
      relationship: "rest",
      primary: null,
      alternates: [],
      coachLine: "Rest is the training decision today. Wait until pain or illness clears before adding load.",
      decision: {
        algorithmVersion: ALGORITHM_VERSION,
        reasons: ["pain_or_illness_flagged"],
        safetyFlags: ["pain_or_illness"],
      },
    };
  }

  if (plan && todayWorkout) {
    if (todayActivities.length > 0 || todayWorkout.status === "completed") {
      return responseWithPrimary({
        base,
        source: "recovery",
        relationship: "optionalRecovery",
        primary: archetypeSuggestion("recovery-walk-20", "You already logged activity today, so this is optional recovery only."),
        alternates: [],
        coachLine: "You already have the meaningful work for today. Only add this if it genuinely helps you loosen up.",
        reasons: ["activity_already_completed_today", "active_plan_present"],
      });
    }

    if (shouldSoftenToday(todayWorkout, athleteState, latestReadiness)) {
      const fallback = archetypeSuggestion(
        recoveryArchetypeFor(todayWorkout.modality),
        "Today's plan is being softened because current readiness or load asks for less stress."
      );
      return responseWithPrimary({
        base,
        source: "plan",
        relationship: "adjustedFromPlan",
        primary: {
          ...fallback,
          plannedWorkoutId: todayWorkout.id,
          optional: false,
        },
        alternates: [],
        coachLine: "Keep the plan alive by lowering the strain today. This protects the next useful workout.",
        reasons: ["active_plan_present", "planned_workout_softened", athleteState.fatigueRisk],
        safetyFlags: athleteState.fatigueRisk === "low" ? [] : [`fatigue_${athleteState.fatigueRisk}`],
      });
    }

    return responseWithPrimary({
      base,
      source: "plan",
      relationship: "todayPlannedWorkout",
      primary: plannedWorkoutSuggestion(todayWorkout, "This is today's planned session."),
      alternates: [],
      coachLine: "This is the next planned step. Keep the effort matched to the prescription.",
      reasons: ["active_plan_present", "today_planned_workout"],
    });
  }

  if (plan && upcomingWorkout) {
    return responseWithPrimary({
      base,
      source: "plan",
      relationship: "planFallback",
      primary: plannedWorkoutSuggestion(upcomingWorkout, "There is no workout specifically scheduled today, so this is the next plan session."),
      alternates: [],
      coachLine: "There is no specific workout on today's calendar. This is the next useful plan step when you are ready.",
      reasons: ["active_plan_present", "no_today_workout", "next_planned_workout"],
    });
  }

  if (todayActivities.length > 0) {
    return responseWithPrimary({
      base,
      source: "recovery",
      relationship: "optionalRecovery",
      primary: archetypeSuggestion("recovery-walk-20", "You already trained today, so this is optional recovery movement."),
      alternates: [],
      coachLine: "The main work is already logged. Keep anything else genuinely easy.",
      reasons: ["activity_already_completed_today", "no_active_plan"],
    });
  }

  const noPlan = chooseNoPlanSuggestion(typedActivities, athleteState, latestReadiness, now);
  return responseWithPrimary({
    base,
    source: noPlan.source,
    relationship: "noPlanSuggestion",
    primary: noPlan.primary,
    alternates: noPlan.alternates,
    coachLine: noPlan.coachLine,
    reasons: noPlan.reasons,
    safetyFlags: noPlan.safetyFlags,
  });
}

function chooseNoPlanSuggestion(
  activities: ActivityForPlanning[],
  athleteState: AthleteTrainingStateSnapshot,
  readiness: ReadinessForPlanning | undefined,
  now: Date
): {
  source: ActivitySuggestionSource;
  primary: ActivitySuggestion;
  alternates: ActivitySuggestion[];
  coachLine: string;
  reasons: string[];
  safetyFlags: string[];
} {
  const latestActivity = activities[0];
  const baselineMinutes = athleteState.fourWeekAvgMinutes;
  const recentSessions = activities.filter((activity) => activity.startedAt >= addDays(now, -7)).length;
  const preferredModality = preferredModalityFrom(activities);
  const lowReadiness = readiness && (readiness.energy <= 2 || readiness.stress >= 4 || readiness.soreness >= 4);

  if (athleteState.fatigueRisk === "high" || lowReadiness) {
    const primary = archetypeSuggestion(
      preferredModality === "bike" ? "recovery-spin-25" : "recovery-run-25",
      "Recent load or readiness points toward recovery rather than harder training."
    );
    return {
      source: "recovery",
      primary,
      alternates: [archetypeSuggestion("recovery-walk-20", "Use this if running or riding feels like too much today.")],
      coachLine: "Make this restorative. The goal is absorbing work, not adding stress.",
      reasons: ["recovery_bias", `fatigue_${athleteState.fatigueRisk}`],
      safetyFlags: athleteState.fatigueRisk === "high" ? ["high_fatigue"] : [],
    };
  }

  if (!latestActivity || baselineMinutes < 45 || recentSessions === 0) {
    return {
      source: "adaptive",
      primary: archetypeSuggestion("walk-run-return-25", "This is a proven return-to-running structure for rebuilding rhythm."),
      alternates: [archetypeSuggestion("easy-walk-25", "Keep it all walking if the jog intervals feel like too much.")],
      coachLine: "Use a walk-run structure today. It gives you real aerobic work without pretending this needs to be a full run.",
      reasons: ["low_or_missing_baseline", "walk_run_return"],
      safetyFlags: [],
    };
  }

  if (
    preferredModality === "run" &&
    baselineMinutes >= 90 &&
    recentSessions >= 3 &&
    readiness &&
    readiness.energy >= 4 &&
    readiness.stress <= 2 &&
    athleteState.fatigueRisk === "low"
  ) {
    return {
      source: "adaptive",
      primary: archetypeSuggestion("easy-run-strides-30", "You have enough recent consistency for easy running with a small relaxed speed touch."),
      alternates: [archetypeSuggestion("easy-run-30", "Use this if you want the same aerobic benefit without strides.")],
      coachLine: "Keep the strides relaxed. They should feel smooth, not like intervals.",
      reasons: ["consistent_recent_running", "readiness_good", "strides_eligible"],
      safetyFlags: [],
    };
  }

  if (preferredModality === "bike") {
    return {
      source: "adaptive",
      primary: archetypeSuggestion("easy-ride-35", "Your recent activity supports a straightforward aerobic ride."),
      alternates: [archetypeSuggestion("recovery-spin-25", "Use this if your legs feel heavier than expected.")],
      coachLine: "Keep the ride smooth and aerobic. You should finish feeling like you could do a little more.",
      reasons: ["bike_preference", "baseline_supports_easy_aerobic"],
      safetyFlags: [],
    };
  }

  return {
    source: "adaptive",
    primary: archetypeSuggestion("easy-run-30", "Your recent activity supports a simple aerobic run."),
    alternates: [archetypeSuggestion("walk-run-return-25", "Use this if you want a gentler structure today.")],
    coachLine: "Keep this conversational. The value is aerobic time, not proving fitness today.",
    reasons: ["baseline_supports_easy_aerobic", "no_active_plan"],
    safetyFlags: [],
  };
}

function plannedWorkoutSuggestion(workout: PlannedWorkoutWithBlocks, why: string): ActivitySuggestion {
  const steps = workout.blocks.flatMap((block) =>
    block.steps.length > 0
      ? block.steps.map((step) => step.label)
      : [`${titleCase(block.blockType)}${block.durationSeconds ? `, ${minutesLabel(block.durationSeconds)}` : ""}`]
  );

  return {
    id: `planned-${workout.id}`,
    title: workout.title,
    modality: toModality(workout.modality),
    stimulus: toStimulus(workout.stimulus),
    durationMinutes: Math.max(1, Math.round(workout.durationSeconds / 60)),
    effortLabel: effortLabelFor(workout.stimulus),
    intensityModel: toIntensityModel(workout.intensityModel),
    intensityTarget: jsonObject(workout.intensityTarget),
    why,
    steps: steps.length > 0 ? steps : [workout.title],
    startLabel: startLabelFor(workout.modality),
    plannedWorkoutId: workout.id,
    archetypeId: null,
    optional: !workout.isKeyWorkout,
  };
}

function archetypeSuggestion(id: string, why: string): ActivitySuggestion {
  const archetype = ARCHETYPES[id];
  if (!archetype) {
    throw new Error(`Unknown activity suggestion archetype: ${id}`);
  }
  return {
    ...archetype,
    why,
    plannedWorkoutId: null,
    archetypeId: id,
  };
}

const ARCHETYPES: Record<string, Omit<ActivitySuggestion, "why" | "plannedWorkoutId" | "archetypeId">> = {
  "recovery-walk-20": {
    id: "recovery-walk-20",
    title: "20 min recovery walk",
    modality: "walk",
    stimulus: "recovery",
    durationMinutes: 20,
    effortLabel: "Very easy",
    intensityModel: "rpe",
    intensityTarget: { min: 1, max: 2 },
    steps: ["20 min relaxed walk"],
    startLabel: "Start walk",
    optional: true,
  },
  "easy-walk-25": {
    id: "easy-walk-25",
    title: "25 min brisk walk",
    modality: "walk",
    stimulus: "easyAerobic",
    durationMinutes: 25,
    effortLabel: "Easy",
    intensityModel: "rpe",
    intensityTarget: { min: 2, max: 4 },
    steps: ["5 min easy walk", "15 min purposeful walk", "5 min easy finish"],
    startLabel: "Start walk",
    optional: false,
  },
  "walk-run-return-25": {
    id: "walk-run-return-25",
    title: "25 min walk-run return",
    modality: "run",
    stimulus: "easyAerobic",
    durationMinutes: 25,
    effortLabel: "Gentle",
    intensityModel: "rpe",
    intensityTarget: { min: 2, max: 4 },
    steps: ["5 min walk", "6 x 1 min jog / 2 min walk", "2 min easy walk finish"],
    startLabel: "Start walk-run",
    optional: false,
  },
  "recovery-run-25": {
    id: "recovery-run-25",
    title: "25 min recovery run",
    modality: "run",
    stimulus: "recovery",
    durationMinutes: 25,
    effortLabel: "Very easy",
    intensityModel: "rpe",
    intensityTarget: { min: 2, max: 3 },
    steps: ["5 min easy warmup", "15 min very easy jog", "5 min easy cooldown"],
    startLabel: "Start run",
    optional: true,
  },
  "easy-run-30": {
    id: "easy-run-30",
    title: "30 min easy run",
    modality: "run",
    stimulus: "easyAerobic",
    durationMinutes: 30,
    effortLabel: "Conversational",
    intensityModel: "rpe",
    intensityTarget: { min: 3, max: 4 },
    steps: ["5 min easy warmup", "20 min relaxed run", "5 min easy cooldown"],
    startLabel: "Start run",
    optional: false,
  },
  "easy-run-strides-30": {
    id: "easy-run-strides-30",
    title: "30 min easy run + strides",
    modality: "run",
    stimulus: "speed",
    durationMinutes: 30,
    effortLabel: "Easy with relaxed speed",
    intensityModel: "rpe",
    intensityTarget: { min: 3, max: 6 },
    steps: ["20 min easy run", "4 x 20 sec relaxed strides with easy walk back", "5 min easy cooldown"],
    startLabel: "Start run",
    optional: false,
  },
  "easy-ride-35": {
    id: "easy-ride-35",
    title: "35 min easy ride",
    modality: "bike",
    stimulus: "easyAerobic",
    durationMinutes: 35,
    effortLabel: "Smooth aerobic",
    intensityModel: "rpe",
    intensityTarget: { min: 3, max: 4 },
    steps: ["5 min easy spin", "25 min smooth aerobic riding", "5 min easy cooldown"],
    startLabel: "Start ride",
    optional: false,
  },
  "recovery-spin-25": {
    id: "recovery-spin-25",
    title: "25 min recovery spin",
    modality: "bike",
    stimulus: "recovery",
    durationMinutes: 25,
    effortLabel: "Very easy",
    intensityModel: "rpe",
    intensityTarget: { min: 1, max: 3 },
    steps: ["25 min light spin, relaxed cadence"],
    startLabel: "Start ride",
    optional: true,
  },
};

function responseWithPrimary(params: {
  base: ActivitySuggestionResponse;
  source: ActivitySuggestionSource;
  relationship: ActivitySuggestionRelationship;
  primary: ActivitySuggestion;
  alternates: ActivitySuggestion[];
  coachLine: string;
  reasons: string[];
  safetyFlags?: string[];
}): ActivitySuggestionResponse {
  return {
    ...params.base,
    status: "suggested",
    source: params.source,
    relationship: params.relationship,
    primary: params.primary,
    alternates: params.alternates,
    coachLine: params.coachLine,
    decision: {
      algorithmVersion: ALGORITHM_VERSION,
      reasons: params.reasons,
      safetyFlags: params.safetyFlags ?? [],
    },
  };
}

function baseResponse(params: {
  now: Date;
  planningStatus: PlanningStatus;
  planVersionId: string | null;
  planContext: ActivitySuggestionResponse["planContext"];
  activities: ActivityForPlanning[];
}): ActivitySuggestionResponse {
  const latestActivity = params.activities[0];
  const validFor = startOfDay(params.now);
  return {
    status: "noSuggestion",
    source: "adaptive",
    relationship: "noPlanSuggestion",
    primary: null,
    alternates: [],
    coachLine: "No activity suggestion is available yet.",
    planningStatus: params.planningStatus,
    generatedAt: params.now.toISOString(),
    validForDate: validFor.toISOString().slice(0, 10),
    validUntil: addDays(validFor, 1).toISOString(),
    planVersionId: params.planVersionId,
    planContext: params.planContext,
    activityWatermark: {
      lastActivityId: latestActivity?.id ?? null,
      lastActivityStartedAt: latestActivity?.startedAt.toISOString() ?? null,
    },
    decision: {
      algorithmVersion: ALGORITHM_VERSION,
      reasons: [],
      safetyFlags: [],
    },
  };
}

function planTitleFromGoal(type: string): string {
  switch (type) {
    case "race":
      return "Race plan";
    case "comeback":
      return "Comeback plan";
    case "strength":
      return "Strength plan";
    default:
      return "Training plan";
  }
}

function shouldSoftenToday(
  workout: PlannedWorkoutWithBlocks,
  athleteState: AthleteTrainingStateSnapshot,
  readiness?: ReadinessForPlanning
): boolean {
  if (athleteState.fatigueRisk === "high") return true;
  if (!readiness) return false;
  const hard = workout.isKeyWorkout || ["threshold", "speed", "longEndurance"].includes(workout.stimulus);
  return hard && (readiness.energy <= 2 || readiness.stress >= 4 || readiness.soreness >= 4);
}

function recoveryArchetypeFor(modality: string): string {
  return modality === "bike" ? "recovery-spin-25" : "recovery-run-25";
}

function plannedWorkoutForState(workout: PlannedWorkoutWithBlocks): PlannedWorkoutForState {
  return {
    id: workout.id,
    scheduledDate: workout.scheduledDate,
    modality: workout.modality,
    stimulus: workout.stimulus,
    durationSeconds: workout.durationSeconds,
    distanceMeters: workout.distanceMeters,
    isKeyWorkout: workout.isKeyWorkout,
    status: workout.status,
  };
}

function readinessForPlanning(readiness: {
  date: Date;
  energy: number;
  soreness: number;
  sleepQuality: number;
  stress: number;
  motivation: number;
  illnessOrPain: boolean;
}): ReadinessForPlanning {
  return {
    date: readiness.date,
    energy: readiness.energy,
    soreness: readiness.soreness,
    sleepQuality: readiness.sleepQuality,
    stress: readiness.stress,
    motivation: readiness.motivation,
    illnessOrPain: readiness.illnessOrPain,
  };
}

function preferredModalityFrom(activities: ActivityForPlanning[]): Modality {
  const counts = new Map<Modality, number>();
  for (const activity of activities) {
    const modality = modalityForActivityType(activity.type);
    counts.set(modality, (counts.get(modality) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "run";
}

function modalityForActivityType(type: string): Modality {
  const normalized = type.toLowerCase();
  if (normalized.includes("walk")) return "walk";
  if (normalized.includes("bike") || normalized.includes("cycl")) return "bike";
  if (normalized.includes("swim")) return "swim";
  if (normalized.includes("strength")) return "strength";
  return "run";
}

function toModality(value: string): Modality {
  switch (value) {
    case "walk":
    case "bike":
    case "swim":
    case "strength":
    case "hiit":
    case "skate":
    case "mobility":
      return value;
    default:
      return "run";
  }
}

function toStimulus(value: string): TrainingStimulus {
  switch (value) {
    case "longEndurance":
    case "threshold":
    case "speed":
    case "strength":
    case "hypertrophy":
    case "power":
    case "skill":
    case "recovery":
    case "mobility":
      return value;
    default:
      return "easyAerobic";
  }
}

function toIntensityModel(value: string): ActivitySuggestion["intensityModel"] {
  switch (value) {
    case "pace":
    case "heartRate":
    case "power":
    case "open":
      return value;
    default:
      return "rpe";
  }
}

function effortLabelFor(stimulus: string): string {
  switch (stimulus) {
    case "threshold":
      return "Controlled hard";
    case "speed":
      return "Fast but relaxed";
    case "longEndurance":
      return "Easy endurance";
    case "recovery":
    case "mobility":
      return "Very easy";
    default:
      return "Conversational";
  }
}

function startLabelFor(modality: string): string {
  switch (modality) {
    case "bike":
      return "Start ride";
    case "walk":
      return "Start walk";
    default:
      return "Start run";
  }
}

function jsonObject(value: Prisma.JsonValue | null): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function minutesLabel(seconds: number): string {
  return `${Math.max(1, Math.round(seconds / 60))} min`;
}

function titleCase(value: string): string {
  return value.replace(/(^|\s|-)\S/g, (char) => char.toUpperCase());
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function sameDay(left: Date, right: Date): boolean {
  return left.toISOString().slice(0, 10) === right.toISOString().slice(0, 10);
}
