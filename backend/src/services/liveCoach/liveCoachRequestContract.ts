import { z } from "zod";
import { SUPPORTED_AI_LOCALES, VOICE_PROFILE_IDS } from "../aiProviders/types.js";
const identifier = z.string().uuid();

const clientWorkoutSchema = z.object({
  title: z.string().trim().min(1).max(120),
  detail: z.string().max(16_000).transform(() => ""),
  guideLine: z.string().max(16_000).transform(() => ""),
  targetDistanceMeters: z.number().finite().min(0).max(1_000_000).optional(),
  targetDurationSeconds: z.number().finite().min(0).max(24 * 60 * 60).optional(),
  targetCalories: z.number().int().min(1).max(20_000).optional(),
  steps: z.array(z.object({
    label: z.string().trim().min(1).max(100),
    durationSeconds: z.number().finite().min(0).max(24 * 60 * 60),
    detail: z.string().trim().max(240).optional(),
    phase: z.enum(["warmup", "easy", "work", "recovery", "walk", "cooldown", "open"]).optional(),
    targetPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
    transitionInstruction: z.string().trim().min(2).max(300).optional(),
    transitionLeadSeconds: z.number().int().min(1).max(30).optional(),
    transitionCountdown: z.enum(["none", "five_second"]).optional(),
  }).strict()).max(80),
  route: z.object({
    name: z.string().trim().max(120).optional(),
    shape: z.string().trim().max(40).optional(),
    direction: z.enum(["forward", "reverse"]).optional(),
    distanceMeters: z.number().finite().min(0).max(1_000_000).optional(),
    elevationGainMeters: z.number().finite().min(0).max(100_000).optional(),
    approximateStartLatitude: z.number().finite().min(-90).max(90).optional(),
    approximateStartLongitude: z.number().finite().min(-180).max(180).optional(),
    approximateStartAltitudeMeters: z.number().finite().min(-500).max(10_000).optional(),
  }).strict().optional(),
}).strict();

const environmentSchema = z.object({
  timeZoneIdentifier: z.string().trim().max(100).optional(),
  indoor: z.boolean(),
  approximateLocation: z.object({
    placeName: z.string().trim().max(120).optional(),
    latitude: z.number().finite().min(-90).max(90).optional(),
    longitude: z.number().finite().min(-180).max(180).optional(),
    altitudeMeters: z.number().finite().min(-500).max(10_000).optional(),
  }).strict().optional(),
  weather: z.object({
    observedAt: z.string().datetime(),
    condition: z.string().trim().min(1).max(100).optional(),
    temperatureCelsius: z.number().finite().min(-100).max(100),
    apparentTemperatureCelsius: z.number().finite().min(-100).max(100),
    windKilometersPerHour: z.number().finite().min(0).max(500),
    precipitationChance: z.number().finite().min(0).max(1),
    impact: z.enum(["none", "advisory", "caution", "unsafe"]),
    headline: z.string().trim().max(180).optional(),
    guidance: z.string().trim().max(300).optional(),
    bestWindow: z.string().trim().max(160).optional(),
  }).strict().optional(),
}).strict();

const baseSessionSchema = z.object({
  contractVersion: z.union([z.literal(1), z.literal(2)]),
  clientSessionId: identifier,
  preparationId: z.string().min(1).max(120).optional(),
  deferPlanning: z.boolean().optional(),
  workoutId: z.string().min(1).max(120).optional(),
  workoutEditId: z.string().max(160).optional(),
  workoutRevision: z.string().length(64).optional(),
  workoutRef: z.object({
    source: z.literal("standalone_catalog"),
    id: z.string().trim().min(1).max(120),
    version: z.number().int().positive().optional(),
  }).strict().optional(),
  locale: z.enum(SUPPORTED_AI_LOCALES),
  coachPersonaId: z.enum(["plainstride_supportive_v1", "plainstride_focused_v1", "plainstride_calm_v1"]),
  voiceProfileId: z.enum(VOICE_PROFILE_IDS),
  coachingContract: z.enum(["quiet", "responsive", "coach_me"]),
  measurementUnitSystem: z.enum(["metric", "imperial"]),
  sessionIntent: z.object({
    activityType: z.enum(["running", "walking", "cycling", "hiking", "swimming", "strength", "mobility"]),
    goalType: z.enum(["workout", "distance", "time", "calories", "freestyle", "race"]),
    race: z.object({
      distanceMeters: z.number().finite().min(1_000).max(100_000),
      goalMode: z.enum(["finish", "target_time", "target_pace"]),
      goalTimeSeconds: z.number().int().min(5 * 60).max(24 * 60 * 60).optional(),
      targetPaceSecondsPerKilometer: z.number().finite().min(120).max(1_200).optional(),
      pacingStrategy: z.enum(["even", "negative_split", "effort_based"]),
      recommendationSource: z.enum(["training_history", "manual", "insufficient_history"]),
    }).strict().optional(),
  }).strict(),
  clientWorkout: clientWorkoutSchema.optional(),
  execution: z.object({
    targetDistanceMeters: z.number().finite().positive().max(1_000_000).optional(),
    targetDurationSeconds: z.number().int().positive().max(86_400).optional(),
    targetCalories: z.number().int().positive().max(20_000).optional(),
    steps: z.array(z.object({
      durationSeconds: z.number().int().nonnegative().max(86_400),
      phase: z.enum(["warmup", "easy", "work", "recovery", "walk", "cooldown", "open"]),
      targetPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
      transitionLeadSeconds: z.number().int().min(1).max(30).optional(),
      transitionCountdown: z.enum(["none", "five_second"]).optional(),
    }).strict()).max(80),
    route: z.object({
      direction: z.enum(["forward", "reverse"]).optional(),
      distanceMeters: z.number().finite().nonnegative().max(1_000_000).optional(),
      elevationGainMeters: z.number().finite().nonnegative().max(100_000).optional(),
      approximateStartLatitude: z.number().finite().min(-90).max(90).optional(),
      approximateStartLongitude: z.number().finite().min(-180).max(180).optional(),
      approximateStartAltitudeMeters: z.number().finite().min(-500).max(10_000).optional(),
    }).strict().optional(),
  }).strict().optional(),
  workoutIssuance: z.object({ id: z.string().min(1).max(160), revision: z.string().regex(/^[a-f0-9]{64}$/) }).strict().optional(),
  environment: environmentSchema.optional(),
  appDistributionHint: z.literal("global").optional(),
}).strict().refine((value) => !(value.workoutId && value.workoutRef), {
  message: "workoutId and workoutRef are mutually exclusive",
}).refine((value) => value.sessionIntent.goalType !== "race" || value.sessionIntent.race != null, {
  message: "race intent is required when goalType is race",
}).refine((value) => value.sessionIntent.goalType === "race" || value.sessionIntent.race == null, {
  message: "race intent is allowed only when goalType is race",
});

export const createSessionSchema = baseSessionSchema.superRefine((value, context) => {
  const issue = (path: string[], message: string) => context.addIssue({ code: "custom", path, message });
  if (value.contractVersion === 2) {
    if (value.clientWorkout) issue(["clientWorkout"], "Use structured execution in contract 2.");
    if (!value.execution) issue(["execution"], "Structured execution is required.");
    if ((value.workoutId || value.workoutRef) && value.execution?.steps.length) {
      issue(["execution", "steps"], "Referenced workout steps are resolved by the server.");
    }
    if (value.workoutIssuance && !value.workoutId) issue(["workoutIssuance"], "Issuance requires a planned workout.");
    if ((value.execution?.steps.reduce((total, step) => total + step.durationSeconds, 0) ?? 0) > 86_400) {
      issue(["execution", "steps"], "Total execution duration exceeds one day.");
    }
    const targetField = { distance: "targetDistanceMeters", time: "targetDurationSeconds", calories: "targetCalories" } as const;
    const goalType = value.sessionIntent.goalType;
    if (goalType in targetField) {
      const field = targetField[goalType as keyof typeof targetField];
      if (value.execution?.[field] == null) issue(["execution", field], "The selected goal requires its numeric target.");
    }
    const environment = value.environment;
    if (environment?.approximateLocation?.placeName !== undefined || environment?.weather &&
        [environment.weather.condition, environment.weather.headline, environment.weather.guidance, environment.weather.bestWindow].some((value) => value !== undefined)) {
      issue(["environment"], "Contract 2 environment uses structured observations only.");
    }
  } else if (value.execution || value.workoutIssuance) issue(["contractVersion"], "Structured execution requires contract 2.");
});
