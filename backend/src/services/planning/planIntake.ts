import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import { z } from "zod";
import { getPrismaClient } from "../prisma.js";

export const PLAN_INTAKE_POLICY_VERSION = "plan-intake-v4";

const objectives = [
  "eventPreparation", "endurance", "speed", "weightLoss",
  "healthEnergy",
] as const;
const activities = ["run", "walk", "bike"] as const;

export const planIntakeInterpretSchema = z.object({
  message: z.string().trim().min(1).max(1_000),
  contextVersion: z.string().min(1).max(240),
  draft: z.object({
    objective: z.enum(objectives).nullable().optional(),
    activities: z.array(z.enum(activities)).max(3).optional(),
    eventDate: z.string().date().nullable().optional(),
    eventDistanceMeters: z.number().positive().nullable().optional(),
    eventIntent: z.enum(["finish", "perform", "targetTime"]).nullable().optional(),
    targetTimeSeconds: z.number().int().positive().nullable().optional(),
    reviewHorizonWeeks: z.number().int().min(4).max(12).nullable().optional(),
    sessionsPerWeek: z.number().int().min(1).max(6).nullable().optional(),
    maxSessionMinutes: z.number().int().min(10).max(180).nullable().optional(),
  }).strict(),
}).strict();

const interpretationSchema = z.object({
  objective: z.enum(objectives).nullable(),
  activities: z.array(z.enum(activities)).max(3),
  eventDate: z.string().date().nullable(),
  eventDistanceMeters: z.number().positive().nullable(),
  eventIntent: z.enum(["finish", "perform", "targetTime"]).nullable(),
  targetTimeSeconds: z.number().int().positive().nullable(),
  reviewHorizonWeeks: z.number().int().min(4).max(12).nullable(),
  goalDescription: z.string().trim().max(500).nullable(),
  recognizedFields: z.array(z.enum([
    "objective", "activities", "eventDate", "eventDistanceMeters", "eventIntent",
    "targetTimeSeconds", "reviewHorizonWeeks", "goalDescription",
  ])).max(8),
  assistantReply: z.string().trim().min(1).max(500),
}).strict();

const interpretationJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["objective", "activities", "eventDate", "eventDistanceMeters", "eventIntent", "targetTimeSeconds", "reviewHorizonWeeks", "goalDescription", "recognizedFields", "assistantReply"],
  properties: {
    objective: { type: ["string", "null"], enum: [...objectives, null] },
    activities: { type: "array", maxItems: 3, items: { type: "string", enum: [...activities] } },
    eventDate: { type: ["string", "null"], format: "date" },
    eventDistanceMeters: { type: ["number", "null"], exclusiveMinimum: 0 },
    eventIntent: { type: ["string", "null"], enum: ["finish", "perform", "targetTime", null] },
    targetTimeSeconds: { type: ["integer", "null"], minimum: 1 },
    reviewHorizonWeeks: { type: ["integer", "null"], enum: [4, 8, 12, null] },
    goalDescription: { type: ["string", "null"], maxLength: 500 },
    recognizedFields: { type: "array", maxItems: 8, items: { type: "string", enum: ["objective", "activities", "eventDate", "eventDistanceMeters", "eventIntent", "targetTimeSeconds", "reviewHorizonWeeks", "goalDescription"] } },
    assistantReply: { type: "string", minLength: 1, maxLength: 500 },
  },
} as const;

type SupportedLocale = "en" | "es" | "zh-Hans";

export async function getPlanIntakeContext(
  userId: string,
  objective?: string | null,
  timeZoneIdentifier?: string | null
) {
  const prisma = getPrismaClient();
  const now = new Date();
  const ninetyDaysAgo = addDays(now, -90);
  const twentyEightDaysAgo = addDays(now, -28);
  const fourteenDaysAgo = addDays(now, -14);
  const [profile, activityHistory, activePlan] = await Promise.all([
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.activity.findMany({
      where: { userId, deletedAt: null, startedAt: { gte: ninetyDaysAgo } },
      orderBy: { startedAt: "desc" },
      select: { id: true, type: true, startedAt: true, durationSecs: true, distanceM: true },
    }),
    prisma.trainingPlan.findFirst({
      where: { userId, status: "active" },
      orderBy: { createdAt: "desc" },
      select: { goal: { select: { preferredDays: true, daysPerWeekTarget: true, maxSessionMinutes: true } } },
    }),
  ]);
  const recent = activityHistory.filter((item) => item.startedAt >= twentyEightDaysAgo && supportedActivity(item.type));
  const distinctWeeks = new Set(recent.map((item) => weekKey(item.startedAt))).size;
  const latest = activityHistory.find((item) => supportedActivity(item.type));
  const hasCurrentActivity = Boolean(latest && latest.startedAt >= fourteenDaysAgo);
  const rich = recent.length >= 6 && distinctWeeks >= 3 && hasCurrentActivity;
  const evidenceState = rich ? "current" : recent.length > 0 ? "limited" : latest ? "historical" : "none";
  const dataTier = rich ? "established" : recent.length > 0 || profile?.completedAt ? "partial" : "new";
  const durations = recent.flatMap((item) => item.durationSecs && item.durationSecs > 0 ? [Math.round(item.durationSecs / 60)] : []);
  const sessionsPerWeek = clamp(Math.round(recent.length / 4), 1, 6);
  const observedActivities = activityMix(recent.map((item) => item.type));
  const preferredDays = preferredDaysFor(recent, sessionsPerWeek, timeZoneIdentifier);
  const suggestedMaxSessionMinutes = suggestedSessionCap(durations, activePlan?.goal.maxSessionMinutes);
  const contextVersion = [PLAN_INTAKE_POLICY_VERSION, profile?.updatedAt.toISOString() ?? "no-profile", latest?.startedAt.toISOString() ?? "no-activity", recent.length].join(":");
  const questions = questionIds({
    objective,
    rich,
    hasRequiredBody: Boolean(profile?.sexAtBirth && profile.birthDate && profile.weightKilograms),
  });

  return {
    contractVersion: 2,
    policyVersion: PLAN_INTAKE_POLICY_VERSION,
    contextVersion,
    dataTier,
    evidenceState,
    questions,
    bodyProfile: {
      sexAtBirth: profile?.sexAtBirth ?? null,
      birthDate: profile?.birthDate?.toISOString().slice(0, 10) ?? null,
      heightCentimeters: profile?.heightCentimeters ?? null,
      weightKilograms: profile?.weightKilograms ?? null,
      completeForPlanning: Boolean(profile?.sexAtBirth && profile.birthDate && profile.weightKilograms),
      source: profile ? "runner_profile" : "unknown",
    },
    observedBaseline: recent.length === 0 ? null : {
      source: "recent_activities",
      confidence: rich ? "high" : "low",
      windowDays: 28,
      sessionCount: recent.length,
      activeWeekCount: distinctWeeks,
      sessionsPerWeek,
      comfortableMinutes: durations.length ? median(durations) : null,
      longestSessionMinutes: durations.length ? Math.max(...durations) : null,
      latestActivityAt: latest?.startedAt.toISOString() ?? null,
      activityMix: observedActivities,
    },
    suggestedSetup: rich ? {
      source: "recent_activities",
      confidence: "high",
      activities: observedActivities,
      baselineContext: "currentlyActive",
      sessionsPerWeek,
      maxSessionMinutes: suggestedMaxSessionMinutes,
      preferredDays,
      evidence: {
        windowDays: 28,
        sessionCount: recent.length,
        activeWeekCount: distinctWeeks,
      },
      requiresConfirmation: true,
    } : null,
    previousSchedule: activePlan ? {
      source: "active_plan",
      preferredDays: activePlan.goal.preferredDays,
      sessionsPerWeek: activePlan.goal.daysPerWeekTarget,
      maxSessionMinutes: activePlan.goal.maxSessionMinutes,
      requiresConfirmation: true,
    } : null,
    requiredBodyFields: ["birthDate", "sexAtBirth", "weightKilograms"],
  };
}

export async function interpretPlanIntake(
  input: z.infer<typeof planIntakeInterpretSchema>,
  locale: SupportedLocale,
  context?: Awaited<ReturnType<typeof getPlanIntakeContext>>
) {
  const fallback = fallbackInterpretation(input.message, locale);
  const generated = await interpretWithGemini(input, locale, context).catch(() => null);
  if (!generated) return fallback;
  const recognizedFields = [...new Set([...generated.recognizedFields, ...fallback.recognizedFields])].slice(0, 8) as typeof generated.recognizedFields;
  const deterministicObjective = fallback.objective;
  return interpretationSchema.parse({
    objective: deterministicObjective ?? generated.objective ?? null,
    activities: generated.activities.length ? generated.activities : fallback.activities,
    eventDate: generated.eventDate,
    eventDistanceMeters: generated.eventDistanceMeters ?? fallback.eventDistanceMeters,
    eventIntent: generated.eventIntent ?? fallback.eventIntent,
    targetTimeSeconds: generated.targetTimeSeconds ?? fallback.targetTimeSeconds,
    reviewHorizonWeeks: generated.reviewHorizonWeeks ?? fallback.reviewHorizonWeeks,
    goalDescription: generated.goalDescription ?? fallback.goalDescription,
    recognizedFields,
    assistantReply: fallback.eventDistanceMeters ? fallback.assistantReply : generated.assistantReply,
  });
}

function questionIds(input: { objective?: string | null; rich: boolean; hasRequiredBody: boolean }) {
  const values = ["objective"];
  if (input.objective === "eventPreparation") values.push("event_details", "event_intent");
  else if (input.objective) values.push("progress_definition", "review_horizon");
  if (input.rich) values.push("training_setup_confirmation", "current_restrictions");
  else values.push("activities", "baseline", "availability", "current_restrictions");
  if (!input.hasRequiredBody) values.push("required_body_profile");
  values.push("assumptions_review");
  return values;
}

async function interpretWithGemini(
  input: z.infer<typeof planIntakeInterpretSchema>,
  locale: SupportedLocale,
  context?: Awaited<ReturnType<typeof getPlanIntakeContext>>
) {
  const project = process.env.GEMINI_VERTEX_PROJECT_ID;
  const apiKey = process.env.GEMINI_API_KEY;
  if (!project && !apiKey) return null;
  const client = apiKey ? new GoogleGenAI({ apiKey, apiVersion: "v1beta" }) : new GoogleGenAI({
    vertexai: true,
    project,
    location: process.env.GEMINI_VERTEX_LOCATION || "global",
    apiVersion: "v1beta1",
  });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.AI_PLANNING_DEADLINE_MILLISECONDS) || 20_000);
  try {
    const response = await client.models.generateContent({
      model: process.env.AI_PLANNING_MODEL || "gemini-3.1-pro-preview",
      contents: JSON.stringify({
        task: "Extract only explicit goal facts from the runner's latest message. Use knownContext to make the acknowledgement relevant and avoid asking for facts Plainstride already knows, but never copy knownContext into recognizedFields. Return null for any field that appears only in currentDraft or knownContext.",
        locale,
        currentDraft: input.draft,
        knownContext: context ? {
          dataTier: context.dataTier,
          evidenceState: context.evidenceState,
          bodyProfileComplete: context.bodyProfile.completeForPlanning,
          observedBaseline: context.observedBaseline,
          suggestedSetup: context.suggestedSetup,
          previousSchedule: context.previousSchedule,
          remainingQuestions: context.questions,
        } : null,
        message: input.message,
      }),
      config: {
        abortSignal: controller.signal,
        systemInstruction: "You are Plainstride's plan-intake interpreter. Known context is trusted, privacy-filtered aggregate product data and may shape the acknowledgement, but it is not a statement in the runner's latest message. Never infer health facts, body measurements, availability, pain, or fitness from wording that does not explicitly state them. Never ask for information present in known context. Map only to the supplied enum values. Keep the reply brief, supportive, and in the requested locale. Return strict JSON.",
        responseMimeType: "application/json",
        responseJsonSchema: interpretationJsonSchema,
        thinkingConfig: { thinkingLevel: ThinkingLevel.LOW },
        temperature: 0.1,
        maxOutputTokens: 800,
      },
    });
    return interpretationSchema.parse(JSON.parse(response.text ?? ""));
  } finally {
    clearTimeout(timeout);
  }
}

function fallbackInterpretation(message: string, locale: SupportedLocale): z.infer<typeof interpretationSchema> {
  const value = message.toLowerCase();
  const recognizedFields: z.infer<typeof interpretationSchema>["recognizedFields"] = [];
  const halfMarathon = /half[-\s]?marathon|media marat[oó]n|半程马拉松|半马/.test(value);
  const marathon = !halfMarathon && /\bmarathon\b|marat[oó]n|马拉松/.test(value);
  const tenK = /\b10\s?k\b|10\s?km|十公里/.test(value);
  const fiveK = /\b5\s?k\b|5\s?km|五公里/.test(value);

  let objective: typeof objectives[number] | null = null;
  if (halfMarathon || marathon || tenK || fiveK || /\brace\b|\bevent\b|carrera|evento|赛事|比赛/.test(value)) objective = "eventPreparation";
  else if (/speed|faster|pace|velocidad|m[aá]s r[aá]pid|速度|更快|配速/.test(value)) objective = "speed";
  else if (/farther|endurance|longer|resistencia|m[aá]s lejos|耐力|更远/.test(value)) objective = "endurance";
  else if (/weight|lose|perder peso|减重|减肥/.test(value)) objective = "weightLoss";
  else if (/health|energy|feel better|salud|energ[ií]a|健康|精力/.test(value)) objective = "healthEnergy";
  if (objective) recognizedFields.push("objective");
  recognizedFields.push("goalDescription");

  let eventDistanceMeters: number | null = null;
  if (halfMarathon) eventDistanceMeters = 21_097.5;
  else if (marathon) eventDistanceMeters = 42_195;
  else if (tenK) eventDistanceMeters = 10_000;
  else if (fiveK) eventDistanceMeters = 5_000;
  if (eventDistanceMeters) recognizedFields.push("eventDistanceMeters");

  const parsedActivities: Array<(typeof activities)[number]> = [];
  if (/\brun|running|correr|corriendo|跑步|跑/.test(value) || objective === "eventPreparation") parsedActivities.push("run");
  if (/\bwalk|walking|hike|hiking|caminar|senderismo|步行|徒步/.test(value)) parsedActivities.push("walk");
  if (/\bbike|biking|cycle|cycling|bici|ciclismo|骑行|自行车/.test(value)) parsedActivities.push("bike");
  if (parsedActivities.length) recognizedFields.push("activities");

  const targetTimeSeconds = parseExplicitTargetTime(value);
  let eventIntent: "finish" | "perform" | "targetTime" | null = null;
  if (targetTimeSeconds || /target (?:a )?time|goal time|tiempo objetivo|目标时间|目标成绩/.test(value)) eventIntent = "targetTime";
  else if (/perform|race well|personal best|\bpb\b|\bpr\b|rendir|marca personal|发挥|个人最好/.test(value)) eventIntent = "perform";
  else if (/finish|complete|terminar|completar|完赛|完成/.test(value)) eventIntent = "finish";
  if (eventIntent) recognizedFields.push("eventIntent");
  if (targetTimeSeconds) recognizedFields.push("targetTimeSeconds");

  const horizonMatch = value.match(/\b(4|8|12)\s*(?:weeks?|wks?|semanas?)\b|(?:4|8|12)\s*周/);
  const horizonValue = horizonMatch?.[1] ?? horizonMatch?.[0]?.match(/4|8|12/)?.[0];
  const reviewHorizonWeeks = horizonValue ? Number(horizonValue) : null;
  if (reviewHorizonWeeks) recognizedFields.push("reviewHorizonWeeks");

  return {
    objective,
    activities: parsedActivities,
    eventDate: null,
    eventDistanceMeters,
    eventIntent,
    targetTimeSeconds,
    reviewHorizonWeeks,
    goalDescription: message.slice(0, 500),
    recognizedFields,
    assistantReply: fallbackAcknowledgement(locale, objective, eventDistanceMeters),
  };
}

function parseExplicitTargetTime(value: string) {
  const clock = value.match(/\b(\d{1,2}):([0-5]\d)\b/);
  if (clock) return Number(clock[1]) * 3_600 + Number(clock[2]) * 60;
  const hours = value.match(/\b(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|horas?|小时)\b/);
  const minutes = value.match(/\b(\d+)\s*(?:minutes?|mins?|minutos?|分钟)\b/);
  if (!hours && !minutes) return null;
  return Math.round(Number(hours?.[1] ?? 0) * 3_600 + Number(minutes?.[1] ?? 0) * 60);
}

function fallbackAcknowledgement(locale: SupportedLocale, objective: typeof objectives[number] | null, distance: number | null) {
  const eventName = distance === 21_097.5 ? "half marathon" : distance === 42_195 ? "marathon" : distance === 10_000 ? "10K" : distance === 5_000 ? "5K" : null;
  if (locale === "es") {
    const localizedEvent = eventName === "half marathon" ? "media maratón" : eventName === "marathon" ? "maratón" : eventName;
    return localizedEvent ? `Entendido: ${localizedEvent}.` : objective ? "Entendido. Revisemos los detalles del objetivo." : "Elige el resultado compatible que mejor encaje.";
  }
  if (locale === "zh-Hans") return eventName ? `好的，目标是${eventName === "half marathon" ? "半程马拉松" : eventName === "marathon" ? "马拉松" : eventName}。` : objective ? "好的，我们来确认目标详情。" : "请选择最符合你的受支持目标。";
  return eventName ? `${eventName[0].toUpperCase()}${eventName.slice(1)} — got it.` : objective ? "Got it. Let’s confirm the goal details." : "Choose the supported outcome that fits best.";
}

function supportedActivity(type: string) {
  const value = type.toLowerCase();
  return value.includes("run") || value.includes("walk") || value.includes("hik") || value.includes("bike") || value.includes("cycl");
}

function activityMix(types: string[]) {
  const counts = new Map<string, number>();
  for (const type of types) {
    const value = type.toLowerCase();
    const modality = value.includes("walk") || value.includes("hik")
      ? "walk"
      : value.includes("bike") || value.includes("cycl") ? "bike" : "run";
    counts.set(modality, (counts.get(modality) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([modality]) => modality);
}

function preferredDaysFor(
  activitiesForSetup: Array<{ startedAt: Date }>,
  sessionsPerWeek: number,
  timeZoneIdentifier?: string | null
) {
  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const formatter = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short" });
  const codes = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  const counts = new Map(codes.map((code) => [code, 0]));
  for (const activity of activitiesForSetup) {
    const code = formatter.format(activity.startedAt).toLowerCase().slice(0, 3);
    if (counts.has(code)) counts.set(code, (counts.get(code) ?? 0) + 1);
  }
  return codes
    .filter((code) => (counts.get(code) ?? 0) > 0)
    .sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0) || codes.indexOf(a) - codes.indexOf(b))
    .slice(0, sessionsPerWeek);
}

function suggestedSessionCap(durations: number[], previousCap?: number | null) {
  if (durations.length === 0) return clamp(previousCap ?? 30, 10, 120);
  const sorted = [...durations].sort((a, b) => a - b);
  const upperTypical = sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.75))];
  return clamp(Math.round(upperTypical / 5) * 5, 10, 120);
}

function safeTimeZoneIdentifier(value?: string | null) {
  if (!value) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format(new Date());
    return value;
  } catch {
    return "UTC";
  }
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.max(minimum, Math.min(maximum, value));
}

function median(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  const midpoint = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[midpoint] : Math.round((sorted[midpoint - 1] + sorted[midpoint]) / 2);
}

function weekKey(date: Date) {
  const start = new Date(date);
  start.setUTCHours(0, 0, 0, 0);
  const day = start.getUTCDay();
  start.setUTCDate(start.getUTCDate() + (day === 0 ? -6 : 1 - day));
  return start.toISOString().slice(0, 10);
}

function addDays(date: Date, days: number) {
  return new Date(date.getTime() + days * 86_400_000);
}
