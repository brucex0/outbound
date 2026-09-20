import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import { z } from "zod";
import { getPrismaClient } from "../prisma.js";
import type { ActivityForPlanning, AthleteTrainingStateSnapshot, PlanningEventType } from "./types.js";
import type { PlanFitAssessment } from "./planFit.js";
import { hasActiveCapability } from "../entitlements.js";

const POLICY_VERSION = "ai-planning-v1";
const candidateIds = ["maintain", "recover", "reduce", "progress"] as const;
const outputSchema = z.object({
  candidateId: z.enum(candidateIds),
  confidence: z.enum(["low", "medium", "high"]),
  reasonCode: z.enum(["fatigue", "soreness", "harderThanExpected", "missedWorkout", "improving"]),
  explanation: z.string().trim().min(1).max(500),
  evidenceSummary: z.array(z.string().trim().min(1).max(140)).max(4),
}).strict();

const responseJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["candidateId", "confidence", "reasonCode", "explanation", "evidenceSummary"],
  properties: {
    candidateId: { type: "string", enum: [...candidateIds] },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
    reasonCode: { type: "string", enum: ["fatigue", "soreness", "harderThanExpected", "missedWorkout", "improving"] },
    explanation: { type: "string", minLength: 1, maxLength: 500 },
    evidenceSummary: { type: "array", maxItems: 4, items: { type: "string", minLength: 1, maxLength: 140 } },
  },
} as const;

type UpcomingWorkout = { id: string; title: string; durationSeconds: number; stimulus: string; scheduledDate: Date; isKeyWorkout: boolean };
type Candidate = { id: typeof candidateIds[number]; factor: number; summary: string };

export async function evaluateAndProposePlanAdjustment(input: {
  userId: string;
  eventType: PlanningEventType;
  eventId: string;
  athleteState: AthleteTrainingStateSnapshot;
  recentActivities?: ActivityForPlanning[];
  planFit?: PlanFitAssessment;
}): Promise<{ status: "proposed" | "unchanged" | "existing"; provider: "gemini" | "fallback"; candidateId: string; adjustmentId?: string; explanation: string }> {
  const prisma = getPrismaClient();
  const existing = await prisma.personalizationAdjustment.findFirst({
    where: { userId: input.userId, status: "proposed" },
    orderBy: { createdAt: "desc" },
  });
  if (existing) return { status: "existing", provider: "fallback", candidateId: "existing", adjustmentId: existing.id, explanation: existing.explanation };

  const [workouts, completions, feedback] = await Promise.all([
    latestUpcomingWorkouts(input.userId),
    prisma.workoutCompletion.findMany({
      where: { userId: input.userId, completedAt: { gte: addDays(new Date(), -28) } },
      orderBy: { completedAt: "desc" }, take: 12,
      select: { durationSeconds: true, perceivedEffort: true, completionQuality: true, plannedWorkout: { select: { durationSeconds: true } } },
    }),
    prisma.workoutFeedback.findMany({
      where: { userId: input.userId, recordedAt: { gte: addDays(new Date(), -28) } },
      orderBy: { recordedAt: "desc" }, take: 12,
      select: { effort: true, continuationCapacity: true },
    }),
  ]);
  if (workouts.length === 0) return { status: "unchanged", provider: "fallback", candidateId: "maintain", explanation: "There are no upcoming planned workouts to recalibrate." };

  const candidates = safeCandidates(input.athleteState, input.eventType);
  const context = {
    trigger: input.eventType,
    athleteState: serializableState(input.athleteState),
    planFit: input.planFit ?? null,
    recentActivities: (input.recentActivities ?? []).slice(0, 12).map((activity) => ({
      startedAt: activity.startedAt.toISOString(),
      type: activity.type,
      durationMinutes: activity.durationSecs == null ? null : Math.round(activity.durationSecs / 60),
      distanceKm: activity.distanceM == null ? null : Math.round(activity.distanceM / 100) / 10,
      avgPaceSecondsPerKm: activity.avgPace,
      avgHeartRate: activity.avgHeartRate,
    })),
    upcoming: workouts.map((workout) => ({
      title: workout.title, durationMinutes: Math.round(workout.durationSeconds / 60), stimulus: workout.stimulus,
      daysFromNow: Math.max(0, Math.round((workout.scheduledDate.getTime() - Date.now()) / 86_400_000)), key: workout.isKeyWorkout,
    })),
    completionResponse: {
      samples: completions.length,
      averageCompletionRatio: average(completions.map((item) => item.durationSeconds && item.plannedWorkout.durationSeconds
        ? item.durationSeconds / item.plannedWorkout.durationSeconds : 1)),
      averagePerceivedEffort: average(completions.flatMap((item) => item.perceivedEffort == null ? [] : [item.perceivedEffort])),
      partialOrHardCount: completions.filter((item) => ["partial", "tooHard"].includes(item.completionQuality)).length,
    },
    feedback: {
      tooHard: feedback.filter((item) => item.effort === "tooHard").length,
      easy: feedback.filter((item) => item.effort === "easy").length,
      aboutRight: feedback.filter((item) => item.effort === "aboutRight").length,
    },
    candidates,
  };

  const aiPlanningAllowed = await hasActiveCapability(prisma, input.userId, "ai_planning_dynamic");
  const generated = aiPlanningAllowed ? await chooseWithGemini(context).catch(() => null) : null;
  const selection = validateSelection(generated ?? fallbackSelection(input.eventType, input.athleteState), candidates, input.athleteState, input.eventType);
  if (selection.candidateId === "maintain") return { status: "unchanged", provider: generated ? "gemini" : "fallback", candidateId: "maintain", explanation: selection.explanation };

  const candidate = candidates.find((item) => item.id === selection.candidateId)!;
  const changes = workouts.slice(0, 3).map((workout) => {
    const minutes = Math.max(15, Math.round((workout.durationSeconds / 60) * candidate.factor / 5) * 5);
    return {
      workoutId: workout.id,
      beforeTitle: workout.title,
      afterTitle: replaceDuration(workout.title, minutes),
      beforeDurationSeconds: workout.durationSeconds,
      afterDurationSeconds: minutes * 60,
      scheduledDate: workout.scheduledDate.toISOString(),
    };
  }).filter((change) => change.beforeDurationSeconds !== change.afterDurationSeconds);
  if (changes.length === 0) return { status: "unchanged", provider: generated ? "gemini" : "fallback", candidateId: selection.candidateId, explanation: selection.explanation };

  const adjustment = await prisma.personalizationAdjustment.create({
    data: {
      userId: input.userId,
      reasonCode: selection.reasonCode,
      explanation: `${selection.explanation} ${selection.evidenceSummary.slice(0, 2).join(" ")}`.trim(),
      requiresConfirmation: true,
      changes,
      policyVersion: `${POLICY_VERSION}:${generated ? "gemini" : "fallback"}:${selection.confidence}`,
    },
  });
  return { status: "proposed", provider: generated ? "gemini" : "fallback", candidateId: selection.candidateId, adjustmentId: adjustment.id, explanation: adjustment.explanation };
}

async function latestUpcomingWorkouts(userId: string): Promise<UpcomingWorkout[]> {
  const plan = await getPrismaClient().trainingPlan.findFirst({
    where: { userId, status: "active" }, orderBy: { createdAt: "desc" },
    select: { versions: { orderBy: { versionNumber: "desc" }, take: 1, select: { workouts: {
      where: { status: "planned", scheduledDate: { gte: startOfDay(new Date()) } }, orderBy: { scheduledDate: "asc" }, take: 6,
      select: { id: true, title: true, durationSeconds: true, stimulus: true, scheduledDate: true, isKeyWorkout: true },
    } } } },
  });
  return plan?.versions[0]?.workouts ?? [];
}

function safeCandidates(state: AthleteTrainingStateSnapshot, eventType: PlanningEventType): Candidate[] {
  const values: Candidate[] = [
    { id: "maintain", factor: 1, summary: "Keep the current schedule unchanged." },
    { id: "recover", factor: 0.6, summary: "Reduce the next sessions substantially to prioritize recovery." },
    { id: "reduce", factor: 0.8, summary: "Reduce the next sessions moderately without adding missed load." },
  ];
  if (state.fatigueRisk === "low" && state.adherenceRate >= 0.8 && !["painFlagged", "workoutMissed", "workoutSkipped"].includes(eventType)) {
    values.push({ id: "progress", factor: 1.08, summary: "Progress the next sessions by no more than eight percent." });
  }
  return values;
}

async function chooseWithGemini(context: unknown): Promise<z.infer<typeof outputSchema> | null> {
  if (process.env.AI_PLANNING_ENABLED === "false") return null;
  const project = process.env.GEMINI_VERTEX_PROJECT_ID;
  const apiKey = process.env.GEMINI_API_KEY;
  if (!project && !apiKey) return null;
  const client = apiKey ? new GoogleGenAI({ apiKey, apiVersion: "v1beta" }) : new GoogleGenAI({
    vertexai: true, project, location: process.env.GEMINI_VERTEX_LOCATION || "global", apiVersion: "v1beta1",
  });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.AI_PLANNING_DEADLINE_MILLISECONDS) || 20_000);
  try {
    const response = await client.models.generateContent({
      model: process.env.AI_PLANNING_MODEL || "gemini-3.1-pro-preview",
      contents: JSON.stringify({
        task: "Select the safest useful near-term training-plan candidate and explain it without diagnosis. Use the recent activity timeline and plan-fit assessment when present; do not treat an old plan prescription as stronger evidence than repeated completed activity.",
        context,
      }),

      config: {
        abortSignal: controller.signal,
        systemInstruction: "You are Plainstride's planning evaluator. Use only supplied evidence, including the recent activity timeline and deterministic plan-fit assessment. Prefer maintaining the plan when evidence is weak, but respect repeated completed activity when the deterministic safety policy allows a bounded adjustment. Never override pain, illness, or fatigue safety constraints. Do not diagnose, repeat private facts, invent measurements, or create an unlisted workout. Return strict JSON.",
        responseMimeType: "application/json", responseJsonSchema, thinkingConfig: { thinkingLevel: ThinkingLevel.HIGH }, temperature: 0.2, maxOutputTokens: 1_200,
      },
    });
    return outputSchema.parse(JSON.parse(response.text ?? ""));
  } finally { clearTimeout(timeout); }
}

function validateSelection(selection: z.infer<typeof outputSchema>, candidates: Candidate[], state: AthleteTrainingStateSnapshot, eventType: PlanningEventType) {
  const allowed = candidates.some((candidate) => candidate.id === selection.candidateId);
  if (!allowed || ((state.fatigueRisk === "high" || eventType === "painFlagged") && selection.candidateId === "progress")) {
    return fallbackSelection(eventType, state);
  }
  return selection;
}

function fallbackSelection(eventType: PlanningEventType, state: AthleteTrainingStateSnapshot): z.infer<typeof outputSchema> {
  if (eventType === "painFlagged" || state.fatigueRisk === "high") return { candidateId: "recover", confidence: "high", reasonCode: "soreness", explanation: "The safest useful change is to reduce near-term load while recovery signals are elevated.", evidenceSummary: ["Current safety signals favor recovery."] };
  if (["workoutMissed", "workoutSkipped"].includes(eventType)) return { candidateId: "reduce", confidence: "medium", reasonCode: "missedWorkout", explanation: "A modest reduction keeps the plan moving without cramming missed work.", evidenceSummary: ["A planned session was missed or skipped."] };
  if (state.fatigueRisk === "medium") return { candidateId: "reduce", confidence: "medium", reasonCode: "fatigue", explanation: "A modest reduction better matches the current recovery picture.", evidenceSummary: ["Recent load or readiness is above the usual comfort range."] };
  return { candidateId: "maintain", confidence: "medium", reasonCode: "improving", explanation: "The current plan remains appropriate.", evidenceSummary: ["No material plan-changing signal was found."] };
}

function serializableState(state: AthleteTrainingStateSnapshot) { return { ...state, asOfDate: state.asOfDate.toISOString(), lastHardWorkoutAt: state.lastHardWorkoutAt?.toISOString() ?? null }; }
function average(values: number[]) { return values.length ? Math.round(values.reduce((sum, value) => sum + value, 0) / values.length * 100) / 100 : null; }
function replaceDuration(title: string, minutes: number) { return /·\s*\d+\s*min\s*$/i.test(title) ? title.replace(/·\s*\d+\s*min\s*$/i, `· ${minutes} min`) : `${title} · ${minutes} min`; }
function startOfDay(date: Date) { const result = new Date(date); result.setHours(0, 0, 0, 0); return result; }
function addDays(date: Date, days: number) { return new Date(date.getTime() + days * 86_400_000); }
