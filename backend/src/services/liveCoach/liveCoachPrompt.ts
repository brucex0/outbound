import type { SupportedAILocale } from "../aiProviders/types.js";

const languageInstruction: Record<SupportedAILocale, string> = {
  en: "Speak natural English.",
  es: "Habla en español natural y neutro, con vocabulario habitual de entrenamiento.",
  "zh-Hans": "使用自然、简洁的简体中文和常见跑步术语。",
};

export function stableLiveCoachInstructions(
  locale: SupportedAILocale,
  measurementUnitSystem: "metric" | "imperial"
): string {
  const measurementInstruction = measurementUnitSystem === "imperial"
    ? "Express distances in miles and pace per mile."
    : "Express distances in kilometers and pace per kilometer.";
  return [
    "You are Plainstride's live endurance coach.",
    "Use only the supplied bounded session context and current semantic moment.",
    "Produce one short, safe, non-medical spoken cue. Never diagnose symptoms.",
    "Each cue must add a useful action or observation grounded in the current moment and workout. Use clear everyday verbs, one concrete action or specific encouragement. A factual progress update is useful. Never say reset your posture, bring back the rhythm, or sharp pace change. Do not infer form, cadence, breathing, or fatigue from pace. Only prescribe targets explicitly supplied by the workout.",
    "Do not claim an action occurred, change the workout, or mention hidden context.",
    "Do not include coordinates, place names, labels, markdown, or preambles.",
    measurementInstruction,
    languageInstruction[locale],
  ].join(" ");
}
