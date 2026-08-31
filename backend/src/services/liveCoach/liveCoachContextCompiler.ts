import { createHash } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import type { LiveCoachCompiledContext } from "../aiProviders/types.js";
import { AIProviderError } from "../aiProviders/errors.js";
import type {
  CompiledLiveCoachSessionContext,
  CreateLiveCoachSessionInput,
  LiveCoachClientWorkout,
  LiveCoachEnvironmentInput,
} from "./liveCoachTypes.js";

const maximumEstimatedTokens = 20_000;
const millisecondsPerDay = 24 * 60 * 60 * 1_000;

export async function compileLiveCoachContext(
  prisma: PrismaClient,
  userId: string,
  input: Pick<CreateLiveCoachSessionInput,
    "workoutId" | "measurementUnitSystem" | "locale" | "sessionIntent" | "clientWorkout" | "environment">
): Promise<CompiledLiveCoachSessionContext> {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * millisecondsPerDay);
  const twentyEightDaysAgo = new Date(now.getTime() - 28 * millisecondsPerDay);
  const [
    user,
    runnerProfile,
    guideProfile,
    workout,
    readiness,
    activities,
    feedback,
    insights,
    beliefs,
    latestModel,
    situationalSignals,
  ] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { bio: true } }),
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.guideProfile.findUnique({ where: { userId } }),
    input.workoutId ? prisma.plannedWorkout.findFirst({
      where: { id: input.workoutId, userId },
      include: { blocks: { orderBy: { sortOrder: "asc" }, include: { steps: { orderBy: { sortOrder: "asc" } } } } },
    }) : null,
    prisma.readinessCheckIn.findFirst({ where: { userId }, orderBy: { date: "desc" } }),
    prisma.activity.findMany({
      where: { userId, deletedAt: null, startedAt: { gte: twentyEightDaysAgo } },
      orderBy: { startedAt: "desc" },
      take: 50,
      select: {
        type: true,
        title: true,
        startedAt: true,
        durationSecs: true,
        distanceM: true,
        elevationM: true,
        avgPace: true,
        avgHeartRate: true,
        calories: true,
      },
    }),
    prisma.workoutFeedback.findMany({
      where: { userId, recordedAt: { gte: twentyEightDaysAgo } },
      orderBy: { recordedAt: "desc" },
      take: 12,
      select: { recordedAt: true, effort: true, continuationCapacity: true, note: true },
    }),
    prisma.runnerInsight.findMany({ where: { userId }, orderBy: { updatedAt: "desc" }, take: 12 }),
    prisma.runnerBelief.findMany({
      where: { userId, status: { in: ["confirmed", "hypothesis"] } },
      orderBy: [{ consequenceLevel: "desc" }, { confidence: "desc" }],
      take: 16,
    }),
    prisma.runnerModelVersion.findFirst({ where: { userId }, orderBy: { versionNumber: "desc" } }),
    prisma.situationalSignal.findMany({
      where: { userId, freshUntil: { gt: now } },
      orderBy: [{ consequenceLevel: "desc" }, { observedAt: "desc" }],
      take: 12,
      select: { type: true, value: true, confidence: true, consequenceLevel: true, possibleEffects: true, scope: true },
    }),
  ]);

  if (input.workoutId && !workout && !input.clientWorkout) {
    throw new AIProviderError("not_eligible", "The selected workout is unavailable for this runner.");
  }

  const sevenDayActivities = activities.filter((activity) => activity.startedAt >= sevenDaysAgo);
  const olderBaselineActivities = activities.filter((activity) => activity.startedAt < sevenDaysAgo);
  const context: LiveCoachCompiledContext = {
    version: 2,
    measurementUnitSystem: input.measurementUnitSystem,
    runnerModelVersion: latestModel?.id ?? "runner-model-empty",
    locale: input.locale,
    activityType: input.sessionIntent.activityType,
    goalType: input.sessionIntent.goalType,
    bio: {
      biography: nullableClip(user?.bio, 600),
      ageYears: ageYears(runnerProfile?.birthDate, now),
      sexAtBirth: nullableClip(runnerProfile?.sexAtBirth, 24),
      heightCentimeters: finiteNumber(runnerProfile?.heightCentimeters),
      weightKilograms: finiteNumber(runnerProfile?.weightKilograms),
      goalSummary: nullableClip(runnerProfile?.goalSummary, 500),
      scheduleSummary: nullableClip(runnerProfile?.scheduleSummary, 500),
      comfortableDurationMinutes: runnerProfile?.comfortableDurationMinutes ?? null,
      recentSessionsPerWeek: runnerProfile?.recentSessionsPerWeek ?? null,
      targetSessionsPerWeek: runnerProfile?.targetSessionsPerWeek ?? null,
      preferredLongRunDay: nullableClip(runnerProfile?.preferredLongRunDay, 24),
      guidanceDetail: nullableClip(runnerProfile?.guidanceDetail, 24),
      constraints: boundedJSON(runnerProfile?.constraints ?? {}, 2_000),
    },
    coachingProfile: {
      fitnessLevel: nullableClip(guideProfile?.fitnessLevel, 40),
      weeklyVolumeKilometers: finiteNumber(guideProfile?.weeklyVolumeKm),
      preferredPaceSecondsPerKilometer: finiteNumber(guideProfile?.preferredPace),
      strengths: (guideProfile?.strengths ?? []).slice(0, 8).map((value) => clip(value, 120)),
      weaknesses: (guideProfile?.weaknesses ?? []).slice(0, 8).map((value) => clip(value, 120)),
      goals: boundedJSON(guideProfile?.goals ?? [], 2_000),
      records: boundedJSON(guideProfile?.records ?? {}, 2_000),
      recentMemorySummary: boundedJSON(guideProfile?.memorySnapshot ?? {}, 3_000),
    },
    workout: workout ? {
      title: clip(workout.title, 120),
      purpose: clip(workout.stimulus, 160),
      durationSeconds: workout.durationSeconds,
      intensityTarget: boundedJSON(workout.intensityTarget, 2_000),
      prescription: boundedJSON(workout.prescription, 5_000),
      blocks: workout.blocks.map((block) => ({
        type: clip(block.blockType, 40),
        modality: clip(block.modality, 40),
        stimulus: clip(block.stimulus, 80),
        durationSeconds: block.durationSeconds,
        distanceMeters: block.distanceMeters,
        repeats: block.repeats,
        restSeconds: block.restSeconds,
        metadata: boundedJSON(block.metadata, 1_000),
        steps: block.steps.map((step) => ({
          label: clip(step.label, 100),
          kind: clip(step.kind, 40),
          durationSeconds: step.durationSeconds,
          distanceMeters: step.distanceMeters,
          target: boundedJSON(step.target, 1_000),
          detail: nullableClip(step.detail, 240),
        })),
      })),
    } : null,
    clientWorkout: sanitizeClientWorkout(input.clientWorkout),
    readiness: readiness ? {
      choice: clip(readiness.choice, 24),
      energy: finiteNumber(readiness.energy),
      soreness: finiteNumber(readiness.soreness),
      sleepQuality: finiteNumber(readiness.sleepQuality),
      stress: finiteNumber(readiness.stress),
      motivation: finiteNumber(readiness.motivation),
      illnessOrPain: readiness.illnessOrPain,
      notes: nullableClip(readiness.notes, 600),
    } : null,
    surveySummary: surveySummary(runnerProfile),
    runnerInsights: insights.map((insight) => `${clip(insight.label, 80)}: ${clip(insight.value, 180)} (${insight.confidence})`),
    runnerBeliefs: beliefs.map((belief) => clip(belief.summary, 220)),
    recentTraining: {
      sevenDayActivities: sevenDayActivities.map((activity) => activitySummary(activity, now)),
      sevenDaySummary: aggregateActivities(sevenDayActivities),
      twentyEightDaySummary: {
        ...aggregateActivities(activities),
        priorTwentyOneDayAveragePerWeek: scaledWeeklyAggregate(olderBaselineActivities, 3),
      },
      recentWorkoutFeedback: feedback.map((item) => ({
        daysAgo: daysAgo(item.recordedAt, now),
        effort: clip(item.effort, 32),
        continuationCapacity: nullableClip(item.continuationCapacity, 40),
        note: nullableClip(item.note, 400),
      })),
    },
    environment: sanitizeEnvironment(input.environment, situationalSignals),
    guidancePriorities: beliefs.filter((belief) => ["effort", "recovery"].includes(belief.kind))
      .slice(0, 6).map((belief) => clip(belief.summary, 180)),
    cuePreferences: beliefs.filter((belief) => belief.kind === "preference")
      .slice(0, 6).map((belief) => clip(belief.summary, 160)),
    safetyRequiresFixedOnly: readiness?.illnessOrPain === true || input.environment?.weather?.impact === "unsafe",
  };

  const serialized = stableStringify(context);
  const estimatedTokens = Math.ceil(serialized.length / 4);
  if (estimatedTokens > maximumEstimatedTokens) {
    throw new AIProviderError("budget_exhausted", "Live-coach planner context exceeds its bounded context budget.");
  }
  return {
    context,
    serialized,
    contextHash: createHash("sha256").update(serialized).digest("hex"),
    estimatedTokens,
  };
}

function sanitizeClientWorkout(workout: LiveCoachClientWorkout | undefined): LiveCoachCompiledContext["clientWorkout"] {
  if (!workout) return null;
  return {
    title: clip(workout.title, 120),
    detail: clip(workout.detail, 400),
    guideLine: clip(workout.guideLine, 400),
    targetDistanceMeters: finiteNumber(workout.targetDistanceMeters),
    targetDurationSeconds: finiteNumber(workout.targetDurationSeconds),
    steps: workout.steps.slice(0, 80).map((step) => ({
      label: clip(step.label, 100),
      durationSeconds: step.durationSeconds,
      detail: nullableClip(step.detail, 240),
      phase: step.phase ?? null,
      targetPaceSecondsPerKilometer: finiteNumber(step.targetPaceSecondsPerKilometer),
    })),
    route: workout.route ? {
      name: nullableClip(workout.route.name, 120),
      shape: nullableClip(workout.route.shape, 40),
      direction: workout.route.direction ?? null,
      distanceMeters: finiteNumber(workout.route.distanceMeters),
      elevationGainMeters: finiteNumber(workout.route.elevationGainMeters),
      approximateStartLatitude: roundedCoordinate(workout.route.approximateStartLatitude),
      approximateStartLongitude: roundedCoordinate(workout.route.approximateStartLongitude),
      approximateStartAltitudeMeters: rounded(workout.route.approximateStartAltitudeMeters, 0),
    } : null,
  };
}

function sanitizeEnvironment(
  environment: LiveCoachEnvironmentInput | undefined,
  signals: Array<{ type: string; value: unknown; confidence: number; consequenceLevel: string; possibleEffects: string[]; scope: unknown }>
): LiveCoachCompiledContext["environment"] {
  const relevantSignals = signals.map((signal) => ({
    type: clip(signal.type, 100),
    value: boundedJSON(signal.value, 800),
    confidence: signal.confidence,
    consequenceLevel: signal.consequenceLevel,
    possibleEffects: signal.possibleEffects.slice(0, 8),
    scope: boundedJSON(signal.scope, 600),
  }));
  return {
    timeZoneIdentifier: nullableClip(environment?.timeZoneIdentifier, 100),
    indoor: environment?.indoor ?? false,
    approximateLocation: environment?.approximateLocation ? {
      placeName: nullableClip(environment.approximateLocation.placeName, 120),
      latitude: roundedCoordinate(environment.approximateLocation.latitude),
      longitude: roundedCoordinate(environment.approximateLocation.longitude),
      altitudeMeters: rounded(environment.approximateLocation.altitudeMeters, 0),
    } : null,
    weather: environment?.weather ? {
      observedAt: environment.weather.observedAt,
      condition: clip(environment.weather.condition, 100),
      temperatureCelsius: rounded(environment.weather.temperatureCelsius, 1),
      apparentTemperatureCelsius: rounded(environment.weather.apparentTemperatureCelsius, 1),
      windKilometersPerHour: rounded(environment.weather.windKilometersPerHour, 1),
      precipitationChance: rounded(environment.weather.precipitationChance, 2),
      impact: environment.weather.impact,
      headline: clip(environment.weather.headline, 180),
      guidance: nullableClip(environment.weather.guidance, 300),
      bestWindow: nullableClip(environment.weather.bestWindow, 160),
      relevantSignals,
    } : relevantSignals.length > 0 ? { relevantSignals } : null,
  };
}

type RunnerProfileResult = NonNullable<Awaited<ReturnType<PrismaClient["runnerProfile"]["findUnique"]>>>;
function surveySummary(profile: RunnerProfileResult | null): string[] {
  if (!profile) return [];
  return [
    profile.goalSummary && `Goals: ${clip(profile.goalSummary, 300)}`,
    profile.scheduleSummary && `Schedule: ${clip(profile.scheduleSummary, 300)}`,
    profile.comfortableDurationMinutes != null && `Comfortable duration: ${profile.comfortableDurationMinutes} minutes`,
    profile.recentSessionsPerWeek != null && `Recent frequency: ${profile.recentSessionsPerWeek} sessions per week`,
    `Target frequency: ${profile.targetSessionsPerWeek} sessions per week`,
    profile.guidanceDetail && `Guidance preference: ${clip(profile.guidanceDetail, 40)}`,
  ].filter((value): value is string => typeof value === "string");
}

type ActivitySummaryInput = {
  type: string;
  title: string | null;
  startedAt: Date;
  durationSecs: number | null;
  distanceM: number | null;
  elevationM: number | null;
  avgPace: number | null;
  avgHeartRate: number | null;
  calories: number | null;
};

function activitySummary(activity: ActivitySummaryInput, now: Date) {
  return {
    daysAgo: daysAgo(activity.startedAt, now),
    type: clip(activity.type, 40),
    title: nullableClip(activity.title, 100),
    durationSeconds: activity.durationSecs,
    distanceMeters: finiteNumber(activity.distanceM),
    elevationGainMeters: finiteNumber(activity.elevationM),
    averagePaceSecondsPerKilometer: finiteNumber(activity.avgPace),
    averageHeartRate: activity.avgHeartRate,
    calories: activity.calories,
  };
}

function aggregateActivities(activities: ActivitySummaryInput[]) {
  const totals = activities.reduce((result, activity) => ({
    durationSeconds: result.durationSeconds + (activity.durationSecs ?? 0),
    distanceMeters: result.distanceMeters + (activity.distanceM ?? 0),
    elevationGainMeters: result.elevationGainMeters + (activity.elevationM ?? 0),
  }), { durationSeconds: 0, distanceMeters: 0, elevationGainMeters: 0 });
  return { activityCount: activities.length, ...totals };
}

function scaledWeeklyAggregate(activities: ActivitySummaryInput[], weeks: number) {
  const aggregate = aggregateActivities(activities);
  return {
    activityCount: rounded(aggregate.activityCount / weeks, 1),
    durationSeconds: rounded(aggregate.durationSeconds / weeks, 0),
    distanceMeters: rounded(aggregate.distanceMeters / weeks, 0),
    elevationGainMeters: rounded(aggregate.elevationGainMeters / weeks, 0),
  };
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value).sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function boundedJSON(value: unknown, maximumCharacters: number): unknown {
  if (value == null) return null;
  try {
    const serialized = JSON.stringify(value);
    return serialized.length <= maximumCharacters
      ? JSON.parse(serialized) as unknown
      : { summary: serialized.slice(0, maximumCharacters), truncated: true };
  } catch {
    return null;
  }
}

function clip(value: string | null | undefined, length: number): string {
  return (value ?? "").trim().replace(/\s+/g, " ").slice(0, length);
}
function nullableClip(value: string | null | undefined, length: number): string | null {
  const result = clip(value, length);
  return result || null;
}
function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
function rounded(value: number | undefined | null, digits: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
}
function roundedCoordinate(value: number | undefined): number | null {
  return rounded(value, 2);
}
function daysAgo(date: Date, now: Date): number {
  return Math.max(0, Math.floor((now.getTime() - date.getTime()) / millisecondsPerDay));
}
function ageYears(birthDate: Date | null | undefined, now: Date): number | null {
  if (!birthDate) return null;
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const beforeBirthday = now.getUTCMonth() < birthDate.getUTCMonth()
    || (now.getUTCMonth() === birthDate.getUTCMonth() && now.getUTCDate() < birthDate.getUTCDate());
  if (beforeBirthday) age -= 1;
  return age >= 13 && age <= 120 ? age : null;
}
