import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { GoogleGenAI } from "@google/genai";
import { z } from "zod";
export const RUBRIC_VERSION = "running-plan-rubric-v3";
export const weights = { goalFit: 25, progression: 25, workoutDose: 20, weeklyBalance: 20, clarity: 10 };
const criterion = z.object({ rating: z.number().int().min(0).max(4).nullable(), evidence: z.string().min(1).max(1200) }).strict();
const plan = z.object({ criteria: z.object({ goalFit: criterion, progression: criterion, workoutDose: criterion, weeklyBalance: criterion, clarity: criterion }).strict(), criticisms: z.array(z.object({ workoutIds: z.array(z.string()).min(1).max(8), severity: z.enum(["major", "minor"]), issue: z.string().min(1).max(1200) }).strict()).max(12) }).strict();
const schema = z.object({ A: plan, B: plan, preference: z.enum(["A", "B", "tie"]), rationale: z.string().min(1).max(1200) }).strict();
export type Judgement = z.infer<typeof schema>;
const criterionJSON = { type: "object", additionalProperties: false, required: ["rating", "evidence"], properties: {
  rating: { type: ["integer", "null"], minimum: 0, maximum: 4 }, evidence: { type: "string", minLength: 1, maxLength: 1200 } } };
const planJSON = { type: "object", additionalProperties: false, required: ["criteria", "criticisms"], properties: {
  criteria: { type: "object", additionalProperties: false, required: Object.keys(weights), properties: Object.fromEntries(Object.keys(weights).map((key) => [key, criterionJSON])) },
  criticisms: { type: "array", maxItems: 12, items: { type: "object", additionalProperties: false, required: ["workoutIds", "severity", "issue"], properties: {
    workoutIds: { type: "array", minItems: 1, maxItems: 8, items: { type: "string" } }, severity: { type: "string", enum: ["major", "minor"] }, issue: { type: "string", minLength: 1, maxLength: 1200 } } } } } };
const responseSchema = { type: "object", additionalProperties: false, required: ["A", "B", "preference", "rationale"], properties: {
  A: planJSON, B: planJSON, preference: { type: "string", enum: ["A", "B", "tie"] }, rationale: { type: "string", minLength: 1, maxLength: 1200 } } };
const generationConfig = { schemaVersion: "judge-json-schema-v1", responseSchema, temperature: .2, maxOutputTokens: 6000 };

const rubric = `You independently review two anonymous synthetic running plans. They are not medical prescriptions and no plan can be certified safe. Do not infer a measured fitness benchmark from routine runs, missing sensors, or a desired race time. No missing-sensor penalty by itself. Synthetic histories and stable-fitness checkpoint assumptions are explicitly labeled. A 14-day window alone does not demonstrate long-term progression; rate progression only to the extent checkpoint/rollout evidence supports it, otherwise rating=null with the reason. Judge feasibility handling, not magical readiness for impossible race goals. Holding a run/walk ratio, duration or source week can be appropriate with unchanged/unknown completion or readiness evidence. Do not require invented fitness improvement or automatic advancement merely because calendar time elapsed. Assess progression only against supplied exposure/adherence evidence; distinguish calendar taper checkpoints from actual adaptive progression. Windows are alternative snapshots, never additive schedules. A same-date manual rebuild with identical evidence should remain stable/idempotent; identical output is correct and must not be criticized as a missing change.
For each criterion, use integer0..4:0=unusable/contradictory;1=major defects;2=mixed/material limitations;3=coherent with minor issues;4=well justified for available evidence. Anchors:
goalFit(25):0 ignores objective/capacity;2 partially fits constraints;4 objective, capacity, time and uncertainty align.
progression(25):0 unjustified abrupt load/catch-up;2 incomplete adaptation/taper;4 conservative evidence-driven progression/recovery across supplied checkpoints. null if unassessable.
workoutDose(20):0 impossible/missing executable phases;2 ambiguous or excessive dose;4 purposeful bounded work/recovery, appropriate experience and exact phases.
weeklyBalance(20):0 clustered hard work/no recovery;2 uneven spacing/mix;4 appropriate mostly-easy mix, long work and recovery within schedule.
clarity(10):0 contradictory/non-executable;2 unclear phase/effort;4 clear coherent guidance, uncertainty and current fitness distinguished from goal.
Do not reward longer/harder/more complex merely for its own sake. Criticisms MUST reference actual supplied evaluationId values, never invent IDs or criticize omitted future weeks as observed failure. Return strict JSON only: {A:{criteria:{goalFit:{rating,evidence},progression:{rating,evidence},workoutDose:{rating,evidence},weeklyBalance:{rating,evidence},clarity:{rating,evidence}},criticisms:[{workoutIds:[...],severity:"major"|"minor",issue}]},B:same,preference:"A"|"B"|"tie",rationale}. Do not compute weighted totals; code does that. Explain evidence rather than general coaching platitudes.`;
export function score(plan: Judgement["A"], commonCriteria?: string[]) {
  let points = 0, coverage = 0;
  for (const [key, weight] of Object.entries(weights)) { if (commonCriteria && !commonCriteria.includes(key)) continue; const value = plan.criteria[key as keyof typeof weights].rating; if (value != null) { points += value / 4 * weight; coverage += weight; } }
  return { score: coverage ? Math.round(points / coverage * 1000) / 10 : null, coverage };
}
export async function judge(input: { payload: unknown; allowedA: Set<string>; allowedB: Set<string>; identity: Record<string, unknown>; cache: string; model: string; project: string; location: string; timeoutMs: number; repeat: number }): Promise<{ result: Judgement; cached: boolean; key: string; usage: Record<string, number | null>; providerStatus: string; attempts: number; validationFailures?: unknown[] }> {
  const prompt = rubric + "\nSynthetic case and anonymous outputs:\n" + JSON.stringify(input.payload);
  const key = createHash("sha256").update(JSON.stringify({ identity: input.identity, prompt, rubric: RUBRIC_VERSION, model: input.model, repeat: input.repeat, generationConfig })).digest("hex");
  mkdirSync(input.cache, { recursive: true });
  const file = join(input.cache, key + ".json");
  const validate = (value: unknown) => { const parsed = schema.parse(value); for (const [letter, allowed] of [["A", input.allowedA], ["B", input.allowedB]] as const) for (const item of parsed[letter].criticisms) if (item.workoutIds.some((id) => !allowed.has(id))) throw new Error("judge_fabricated_workout_reference"); return parsed; };
  if (existsSync(file)) {
    const cached = JSON.parse(readFileSync(file, "utf8"));
    return { result: validate(cached.result), usage: cached.usage, cached: true, key, providerStatus: "cached_success", attempts: 0, validationFailures: cached.validationFailures };
  }
  const client = new GoogleGenAI({ vertexai: true, project: input.project, location: input.location });
  let last = "judge_failed";
  const validationFailures: unknown[] = [];
  let usage: Record<string, number | null> = { inputTokens: null, outputTokens: null, totalTokens: null, thinkingTokens: null };
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await client.models.generateContent({ model: input.model, contents: prompt,
        config: { responseMimeType: "application/json", responseJsonSchema: responseSchema, temperature: generationConfig.temperature, maxOutputTokens: generationConfig.maxOutputTokens, abortSignal: AbortSignal.timeout(input.timeoutMs) } });
      usage = { inputTokens: response.usageMetadata?.promptTokenCount ?? null, outputTokens: response.usageMetadata?.candidatesTokenCount ?? null,
        totalTokens: response.usageMetadata?.totalTokenCount ?? null, thinkingTokens: response.usageMetadata?.thoughtsTokenCount ?? null };
      const result = validate(JSON.parse(response.text ?? ""));
      writeFileSync(file, JSON.stringify({ result, usage, validationFailures, originalAttempts: attempt + 1 }, null, 2)); return { result, usage, cached: false, key, providerStatus: "success", attempts: attempt + 1, validationFailures };
    } catch (error) {
      last = error instanceof z.ZodError ? "judge_invalid_schema" : error instanceof SyntaxError ? "judge_invalid_json" : error instanceof Error && error.message === "judge_fabricated_workout_reference" ? error.message : "judge_provider_or_timeout";
      validationFailures.push({ attempt: attempt + 1, category: last,
        issues: error instanceof z.ZodError ? error.issues.slice(0, 8).map((issue) => ({ path: issue.path.join("."), code: issue.code })) : [],
        httpStatus: typeof (error as { status?: unknown }).status === "number" ? (error as { status: number }).status : null });
    }
  }
  throw Object.assign(new Error(last), { usage, attempts: 2, validationFailures });
}
