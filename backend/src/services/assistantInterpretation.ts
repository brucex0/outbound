import { z } from "zod";
import { ThinkingLevel } from "@google/genai";
import { generateStructuredAI } from "./aiReliability/structuredGeneration.js";
import { localeInstruction, type SupportedLocale } from "../middleware/locale.js";

// Same bounded contract as iOS LocalAssistantInterpretation. This endpoint only
// extracts intent; validation and confirmation remain at the execution boundary.
const enums = {
  kind: ["manualWorkout", "prepareActivity", "navigate", "conversation", "cancelManualWorkout"],
  capability: ["discover", "navigate", "support", "brainstorm", "plan"],
  task: ["answer_training_question", "adapt_today", "prepare_week", "post_run_reflection", "live_guidance", "inspect_memory", "product_help"],
  destination: ["social", "today", "me", "settings", "appearance", "settingsAppleMusic", "settingsAppleHealth", "guideSettings", "activityHistory"],
  sport: ["run", "bike", "walk", "hike", "swim", "strength", "mobility"],
  distanceUnit: ["meters", "kilometers", "miles"],
  paceUnit: ["kilometers", "miles"],
} as const;
const numberFields = ["durationHours", "durationMinutes", "durationSeconds", "distanceValue", "paceMinutes", "paceSeconds"] as const;
const textFields = ["localDate", "localTime", "clarification"] as const;
const nullableNumber = z.number().finite().nonnegative().max(1_000_000).nullable();
export const assistantInterpretationSchema = z.object({
  kind: z.enum(enums.kind), capability: z.enum(enums.capability), task: z.enum(enums.task),
  destination: z.enum(enums.destination).nullable(), sport: z.enum(enums.sport).nullable(),
  durationHours: nullableNumber, durationMinutes: nullableNumber, durationSeconds: nullableNumber,
  distanceValue: nullableNumber, distanceUnit: z.enum(enums.distanceUnit).nullable(),
  paceMinutes: nullableNumber, paceSeconds: nullableNumber, paceUnit: z.enum(enums.paceUnit).nullable(),
  localDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  localTime: z.string().regex(/^\d{2}:\d{2}$/).nullable(),
  isIndoor: z.boolean().nullable(), clarification: z.string().max(600).nullable(),
});
export const assistantInterpretRequestSchema = z.object({
  prompt: z.string().min(1).max(4_000),
  context: z.string().max(8_000),
  messages: z.array(z.object({ role: z.enum(["user", "assistant"]), text: z.string().max(1_000) })).max(6),
});

const responseSchema = {
  type: "object", additionalProperties: false,
  properties: {
    ...Object.fromEntries(Object.entries(enums).map(([key, values]) => [key, {
      type: ["kind", "capability", "task"].includes(key) ? "string" : ["string", "null"], enum: ["kind", "capability", "task"].includes(key) ? values : [...values, null],
    }])),
    ...Object.fromEntries(numberFields.map(key => [key, { type: ["number", "null"], minimum: 0, maximum: 1_000_000 }])),
    ...Object.fromEntries(textFields.map(key => [key, { type: ["string", "null"] }])),
    isIndoor: { type: ["boolean", "null"] },
  },
  required: [...Object.keys(enums), ...numberFields, ...textFields, "isIndoor"],
};

export async function interpretAssistant(
  input: z.infer<typeof assistantInterpretRequestSchema>, locale: SupportedLocale
): Promise<z.infer<typeof assistantInterpretationSchema>> {
  const result = await generateStructuredAI({
    operation: "assistant", model: process.env.APP_AI_MODEL || "gemini-3.8-flash", deadlineMilliseconds: 12_000,
    parameters: {
      contents: JSON.stringify(input),
      config: {
        systemInstruction: `Interpret one Plainstride assistant turn. Never execute actions or claim success.
Understand multilingual language, number words, negation, corrections, and follow-up references.
Use manualWorkout to log an already completed activity or continue the supplied draft; prepareActivity only
for an explicit request to prepare a NEW activity; navigate only to explicitly open an allowed destination;
cancelManualWorkout only to cancel the draft; otherwise conversation. Questions, negated commands, hypothetical commands, and quoted commands are not activity requests.
Changes to today's existing workout or training plan are conversation; existing server workflows own these mutations.
Use the provided context and history only to resolve references. Extract only explicitly supplied or unambiguously corrected fields.
Extract new or corrected values only from the latest prompt; history is reference context, not new input.
Missing fields MUST be null, not copied from prior drafts or inferred from typical workouts.
Extract duration components separately: one hour thirty minutes = durationHours 1, durationMinutes 30.
Distance is distanceValue with meters/kilometers/miles; pace is paceMinutes and paceSeconds per kilometers/miles.
For pace without a per-unit, use the stated distance unit or measurement preference.
Do not convert units or compute pace-derived duration. localDate is YYYY-MM-DD and localTime HH:mm in the person's time zone.
Resolve relative dates against the supplied current date; leave unspecified time null. isIndoor false means explicitly outdoors.
If ambiguous, use conversation (or manualWorkout with missing fields during an ongoing log) and a brief clarification.
clarification is null for clear requests and routine missing draft fields; the client asks for missing fields.
Only use destinations from the catalog. Route product questions to product_help, plan changes to adapt_today or prepare_week,
training questions to answer_training_question. Do not diagnose health issues or invent workout or plan data.
${localeInstruction(locale)}`,
        responseMimeType: "application/json", responseJsonSchema: responseSchema,
        thinkingConfig: { thinkingLevel: ThinkingLevel.LOW }, maxOutputTokens: 4_800, temperature: 0,
      },
    },
    validate: response => assistantInterpretationSchema.parse(JSON.parse(response.text || "")),
  });
  return result.value;
}
