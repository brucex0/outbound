import { createHash } from "node:crypto";
import { GoogleGenAI, ThinkingLevel } from "@google/genai";
import { z } from "zod";
import type { LiveCoachCompiledContext } from "../aiProviders/types.js";
import { findCoachPersona } from "./liveCoachCatalog.js";
import { fixedFallbackEnvelope } from "./liveCoachFallback.js";
import { loadLiveCoachFeatureConfig, type LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";
import {
  LIVE_COACH_MOMENTS,
  type LiveCoachGuidancePhase,
  type LiveCoachGuidancePlan,
  type LiveCoachMoment,
} from "./liveCoachTypes.js";

export const LIVE_COACH_PLANNER_PROMPT_VERSION = "2026-08-30.1";

const phases = ["any", "warmup", "easy", "work", "recovery", "walk", "cooldown", "open"] as const;
const plannerCueSchema = z.object({
  moment: z.enum(LIVE_COACH_MOMENTS),
  phases: z.array(z.enum(phases)).min(1).max(8),
  cooldownSeconds: z.number().int().min(45).max(900),
  phrases: z.array(z.string().trim().min(2).max(180)).min(1).max(3),
}).strict();
const plannerOutputSchema = z.object({
  summary: z.string().trim().min(1).max(320),
  progressPolicy: z.object({
    announceEverySeconds: z.number().int().min(120).max(900),
    announceEveryMeters: z.number().int().min(500).max(10_000),
    includePace: z.boolean(),
  }).strict(),
  cues: z.array(plannerCueSchema).min(LIVE_COACH_MOMENTS.length).max(LIVE_COACH_MOMENTS.length * 2),
}).strict();

const plannerJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "progressPolicy", "cues"],
  properties: {
    summary: { type: "string", minLength: 1, maxLength: 320 },
    progressPolicy: {
      type: "object",
      additionalProperties: false,
      required: ["announceEverySeconds", "announceEveryMeters", "includePace"],
      properties: {
        announceEverySeconds: { type: "integer", minimum: 120, maximum: 900 },
        announceEveryMeters: { type: "integer", minimum: 500, maximum: 10_000 },
        includePace: { type: "boolean" },
      },
    },
    cues: {
      type: "array",
      minItems: LIVE_COACH_MOMENTS.length,
      maxItems: LIVE_COACH_MOMENTS.length * 2,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["moment", "phases", "cooldownSeconds", "phrases"],
        properties: {
          moment: { type: "string", enum: [...LIVE_COACH_MOMENTS] },
          phases: { type: "array", minItems: 1, maxItems: 8, items: { type: "string", enum: [...phases] } },
          cooldownSeconds: { type: "integer", minimum: 45, maximum: 900 },
          phrases: { type: "array", minItems: 1, maxItems: 3, items: { type: "string", minLength: 2, maxLength: 180 } },
        },
      },
    },
  },
} as const;

export type GuidancePlannerResult = {
  plan: LiveCoachGuidancePlan;
  planHash: string;
  status: "generated" | "fallback";
  model: string | null;
  promptVersion: string;
  inputTokens?: number;
  outputTokens?: number;
};

export async function generateLiveCoachGuidancePlan(
  context: LiveCoachCompiledContext,
  coachPersonaId: string,
  config: LiveCoachFeatureConfig = loadLiveCoachFeatureConfig()
): Promise<GuidancePlannerResult> {
  const fallback = fallbackGuidancePlan(context);
  if (!config.planner.enabled) return resultForPlan(fallback, "fallback", null);
  const persona = findCoachPersona(coachPersonaId);
  if (!persona) return resultForPlan(fallback, "fallback", null);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.planner.deadlineMilliseconds);
  try {
    const client = config.planner.apiKey
      ? new GoogleGenAI({ apiKey: config.planner.apiKey, apiVersion: "v1beta" })
      : new GoogleGenAI({
          vertexai: true,
          project: config.planner.projectId,
          location: config.planner.location,
          apiVersion: "v1beta1",
        });
    const response = await client.models.generateContent({
      model: config.planner.model,
      contents: JSON.stringify({
        task: "Create the executable live-coaching phrase plan for this workout.",
        supportedMoments: LIVE_COACH_MOMENTS,
        runnerContext: context,
      }),
      config: {
        abortSignal: controller.signal,
        systemInstruction: plannerInstructions(context.locale, persona.instructions),
        responseMimeType: "application/json",
        responseJsonSchema: plannerJSONSchema,
        thinkingConfig: { thinkingLevel: ThinkingLevel.HIGH },
        temperature: 0.45,
        maxOutputTokens: 8_192,
      },
    });
    const parsed = plannerOutputSchema.parse(JSON.parse(response.text ?? ""));
    const plan = normalizeGeneratedPlan(parsed, context);
    return {
      ...resultForPlan(plan, "generated", response.modelVersion ?? config.planner.model),
      inputTokens: response.usageMetadata?.promptTokenCount,
      outputTokens: response.usageMetadata?.candidatesTokenCount,
    };
  } catch {
    return resultForPlan(fallback, "fallback", null);
  } finally {
    clearTimeout(timeout);
  }
}

export function phraseForPlan(
  plan: LiveCoachGuidancePlan,
  phraseId: string,
  moment: LiveCoachMoment,
  phase?: Exclude<LiveCoachGuidancePhase, "any">
): string | null {
  for (const cue of plan.cues) {
    if (cue.moment !== moment || (phase && !cue.phases.includes("any") && !cue.phases.includes(phase))) continue;
    const phrase = cue.phrases.find((candidate) => candidate.id === phraseId);
    if (phrase) return phrase.text;
  }
  return null;
}

function normalizeGeneratedPlan(
  output: z.infer<typeof plannerOutputSchema>,
  context: LiveCoachCompiledContext
): LiveCoachGuidancePlan {
  const grouped = new Map<LiveCoachMoment, z.infer<typeof plannerCueSchema>[]>();
  for (const cue of output.cues) {
    const current = grouped.get(cue.moment) ?? [];
    if (current.length < 2) current.push(cue);
    grouped.set(cue.moment, current);
  }
  const fallback = fallbackGuidancePlan(context);
  const cues = LIVE_COACH_MOMENTS.flatMap((moment) => {
    const generated = grouped.get(moment);
    if (!generated?.length) return fallback.cues.filter((cue) => cue.moment === moment);
    return generated.map((cue, cueIndex) => ({
      id: `${moment}.${cueIndex}`,
      moment,
      phases: deduplicatedPhases(cue.phases),
      priority: urgencyForMoment(moment),
      cooldownSeconds: cue.cooldownSeconds,
      phrases: cue.phrases.map((text, phraseIndex) => ({
        id: `${moment}.${cueIndex}.${phraseIndex}`,
        text: validatePhrase(text, context.locale),
      })),
    }));
  });
  const provisional = {
    contractVersion: 1 as const,
    planVersion: "pending",
    locale: context.locale,
    summary: output.summary,
    progressPolicy: output.progressPolicy,
    cues,
  };
  return { ...provisional, planVersion: planHash(provisional).slice(0, 16) };
}

function fallbackGuidancePlan(context: LiveCoachCompiledContext): LiveCoachGuidancePlan {
  const progressDistance = context.activityType === "cycling"
    ? context.measurementUnitSystem === "imperial" ? 8_047 : 5_000
    : context.measurementUnitSystem === "imperial" ? 1_609 : 1_000;
  const provisional = {
    contractVersion: 1 as const,
    planVersion: "pending",
    locale: context.locale,
    summary: context.locale === "zh-Hans" ? "使用安全、清晰的默认实时指导。"
      : context.locale === "es" ? "Usa orientación predeterminada, segura y clara."
      : "Uses safe, clear default live guidance.",
    progressPolicy: { announceEverySeconds: 300, announceEveryMeters: progressDistance, includePace: true },
    cues: LIVE_COACH_MOMENTS.map((moment) => {
      const fallback = fixedFallbackEnvelope({
        cueRequestId: "00000000-0000-0000-0000-000000000000",
        moment,
        locale: context.locale,
        validForMilliseconds: 5_000,
        result: "success",
        source: "fixed_pack",
      });
      return {
        id: `${moment}.0`,
        moment,
        phases: ["any" as const],
        priority: urgencyForMoment(moment),
        cooldownSeconds: defaultCooldown(moment),
        phrases: [{ id: `${moment}.0.0`, text: fallback.transcript }],
      };
    }),
  };
  return { ...provisional, planVersion: planHash(provisional).slice(0, 16) };
}

function plannerInstructions(locale: string, personaInstructions: string): string {
  return [
    "You are designing a live coaching plan, not replying to the runner.",
    `Write every spoken phrase in locale ${locale}.`,
    personaInstructions,
    "Use every supported moment at least once. Use phases to specialize wording where the workout structure benefits.",
    "Each phrase must be one natural, immediately speakable sentence of at most 24 English/Spanish words or 48 Chinese characters.",
    "Do not include placeholders, metric values, markdown, medical diagnoses, commands to exceed the prescribed workout, or claims about facts not present in context.",
    "Never speak private bio, health, location, survey, or weather details explicitly. Use them only to choose safe tone, focus, timing, and advice.",
    "Progress phrases are fallback wording only; the device will produce exact live distance, time, and pace announcements.",
    "Return only JSON matching the response schema.",
  ].join("\n");
}

function validatePhrase(value: string, locale: string): string {
  const phrase = value.trim().replace(/\s+/g, " ").slice(0, 180);
  const equivalent = locale === "zh-Hans"
    ? phrase.replace(/\s/g, "").length / 2
    : phrase.split(/\s+/).filter(Boolean).length;
  if (!phrase || equivalent > 28 || /\{[^}]+\}|<[^>]+>|```/.test(phrase)) {
    throw new Error("Planner phrase failed semantic validation.");
  }
  return phrase;
}

function resultForPlan(
  plan: LiveCoachGuidancePlan,
  status: "generated" | "fallback",
  model: string | null
): GuidancePlannerResult {
  return {
    plan,
    planHash: planHash(plan),
    status,
    model,
    promptVersion: LIVE_COACH_PLANNER_PROMPT_VERSION,
  };
}

function planHash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function deduplicatedPhases(value: LiveCoachGuidancePhase[]): LiveCoachGuidancePhase[] {
  const phases = [...new Set(value)];
  return phases.includes("any") ? ["any"] : phases;
}

function defaultCooldown(moment: LiveCoachMoment): number {
  if (["unexpected_stop", "resume_after_break", "segment_transition"].includes(moment)) return 45;
  if (moment === "progress") return 180;
  return 120;
}
