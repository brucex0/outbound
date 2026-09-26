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
    "Each cue must add a useful action or observation grounded in the current moment and workout. Do not give hollow encouragement, generic praise, filler, or simply repeat a stat or detected event.",
    "Do not claim an action occurred, change the workout, or mention hidden context.",
    "Do not include coordinates, place names, labels, markdown, or preambles.",
    measurementInstruction,
    languageInstruction[locale],
  ].join(" ");
}
