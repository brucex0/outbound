import { createHash } from "node:crypto";
import type { LiveCoachLiveState, SupportedAILocale } from "../aiProviders/types.js";
import { validateLiveCoachOutput } from "./liveCoachOutputValidation.js";
import type { LiveCoachMoment } from "./liveCoachTypes.js";

const authoredVariants: Record<SupportedAILocale, Partial<Record<Exclude<LiveCoachMoment, "progress">, string[]>>> = {
  en: {
    pace_drift: [
      "Relax your shoulders, quicken the rhythm slightly, and rebuild smoothly.",
      "Reset your posture and bring the pace back one calm step at a time.",
    ],
    rhythm_recovery: [
      "That adjustment worked. Keep this relaxed rhythm.",
      "You found the rhythm again. Stay loose and let it carry you.",
    ],
    segment_transition: [
      "New segment. Settle into the target before adding pressure.",
      "The next segment starts now. Find control first, then build.",
    ],
    finish_opportunity: [
      "If it feels available, lift gradually and keep your form composed.",
      "Stay controlled and let the effort rise smoothly toward the finish.",
    ],
    challenge_start: [
      "Challenge starts now. Build the pace smoothly and stay controlled.",
      "Begin the challenge with control, then let the rhythm grow.",
    ],
    challenge_complete: [
      "Challenge complete. Ease back into your sustainable rhythm.",
      "Nice work. Let the effort settle and return to your normal rhythm.",
    ],
  },
  es: {
    pace_drift: [
      "Relaja los hombros, ajusta la cadencia y recupera el ritmo con calma.",
      "Corrige la postura y vuelve al ritmo poco a poco.",
    ],
    rhythm_recovery: [
      "Ese ajuste funcionó. Mantén este ritmo relajado.",
      "Recuperaste el ritmo. Sigue suelto y deja que te acompañe.",
    ],
    segment_transition: [
      "Nuevo segmento. Encuentra el objetivo antes de aumentar el esfuerzo.",
      "Empieza el siguiente segmento con control y aumenta después.",
    ],
    finish_opportunity: [
      "Si te sientes bien, aumenta gradualmente y mantén una postura estable.",
      "Mantén el control y aumenta el esfuerzo suavemente hasta el final.",
    ],
    challenge_start: [
      "Empieza el reto. Aumenta el ritmo con suavidad y control.",
      "Comienza con control y deja que el ritmo crezca.",
    ],
    challenge_complete: [
      "Reto completado. Vuelve con calma a tu ritmo sostenible.",
      "Buen trabajo. Reduce el esfuerzo y recupera tu ritmo normal.",
    ],
  },
  "zh-Hans": {
    pace_drift: [
      "放松肩膀，稍微加快步频，平稳找回节奏。",
      "调整姿势，一点一点把配速带回来。",
    ],
    rhythm_recovery: [
      "刚才的调整有效，保持现在放松的节奏。",
      "节奏回来了，继续放松，让它自然带着你前进。",
    ],
    segment_transition: [
      "进入新阶段，先稳定到目标强度，再逐步发力。",
      "下一阶段开始，先保持控制，再慢慢提升。",
    ],
    finish_opportunity: [
      "如果状态允许，逐步提升强度，同时保持动作稳定。",
      "保持控制，平稳加力到终点。",
    ],
    challenge_start: [
      "挑战开始，平稳提速，保持控制。",
      "先稳住，再让节奏逐渐加快。",
    ],
    challenge_complete: [
      "挑战完成，放松强度，回到可持续的节奏。",
      "做得好，慢慢收住强度，回到正常节奏。",
    ],
  },
};

export function transcriptForLiveCoachCue(input: {
  locale: SupportedAILocale;
  moment: LiveCoachMoment;
  liveState: LiveCoachLiveState;
  cueRequestId: string;
  measurementUnitSystem: "metric" | "imperial";
}): string {
  if (input.moment === "progress") {
    return progressTranscript(input.locale, input.liveState, input.measurementUnitSystem);
  }
  const variants = authoredVariants[input.locale][input.moment] ?? defaultVariants[input.locale];
  const index = createHash("sha256").update(input.cueRequestId).digest().readUInt32BE(0) % variants.length;
  return validateLiveCoachOutput(variants[index]);
}

const defaultVariants: Record<SupportedAILocale, string[]> = {
  en: ["Keep the effort controlled and stay with a smooth rhythm."],
  es: ["Mantén el esfuerzo controlado y sigue con un ritmo fluido."],
  "zh-Hans": ["保持强度可控，继续维持顺畅的节奏。"],
};

function progressTranscript(
  locale: SupportedAILocale,
  state: LiveCoachLiveState,
  unitSystem: "metric" | "imperial"
): string {
  const distance = unitSystem === "imperial" ? state.distanceMeters / 1_609.344 : state.distanceMeters / 1_000;
  const elapsed = durationParts(state.elapsedSeconds);
  const paceSecondsPerKilometer = usablePace(state.rollingPaceSecondsPerKilometer)
    ?? usablePace(state.currentPaceSecondsPerKilometer)
    ?? averagePace(state.elapsedSeconds, state.distanceMeters);
  const paceSeconds = paceSecondsPerKilometer == null
    ? null
    : paceSecondsPerKilometer * (unitSystem === "imperial" ? 1.609344 : 1);
  const pace = paceSeconds == null ? null : durationParts(paceSeconds);
  const distanceText = decimalDistance(distance);

  if (locale === "zh-Hans") {
    const distanceUnit = unitSystem === "imperial" ? "英里" : "公里";
    const paceUnit = unitSystem === "imperial" ? "每英里" : "每公里";
    const paceText = pace ? `，配速${paceUnit}${chineseDuration(pace)}` : "";
    return validateLiveCoachOutput(`距离${distanceText}${distanceUnit}，用时${chineseDuration(elapsed)}${paceText}。`);
  }
  if (locale === "es") {
    const distanceUnit = unitSystem === "imperial" ? "millas" : "kilómetros";
    const paceUnit = unitSystem === "imperial" ? "por milla" : "por kilómetro";
    const paceText = pace ? `, ritmo de ${spanishDuration(pace)} ${paceUnit}` : "";
    return validateLiveCoachOutput(`${distanceText} ${distanceUnit}, ${spanishDuration(elapsed)}${paceText}.`);
  }
  const distanceUnit = unitSystem === "imperial" ? "miles" : "kilometers";
  const paceUnit = unitSystem === "imperial" ? "per mile" : "per kilometer";
  const paceText = pace ? `, pace ${englishDuration(pace)} ${paceUnit}` : "";
  return validateLiveCoachOutput(`${distanceText} ${distanceUnit}, ${englishDuration(elapsed)}${paceText}.`);
}

function durationParts(secondsValue: number): { minutes: number; seconds: number } {
  const rounded = Math.max(0, Math.round(secondsValue));
  return { minutes: Math.floor(rounded / 60), seconds: rounded % 60 };
}

function englishDuration(value: { minutes: number; seconds: number }): string {
  const minutes = `${value.minutes} ${value.minutes === 1 ? "minute" : "minutes"}`;
  return value.seconds === 0 ? minutes : `${minutes} ${value.seconds} seconds`;
}

function spanishDuration(value: { minutes: number; seconds: number }): string {
  const minutes = `${value.minutes} ${value.minutes === 1 ? "minuto" : "minutos"}`;
  return value.seconds === 0 ? minutes : `${minutes} y ${value.seconds} segundos`;
}

function chineseDuration(value: { minutes: number; seconds: number }): string {
  return value.seconds === 0 ? `${value.minutes}分钟` : `${value.minutes}分${value.seconds}秒`;
}

function usablePace(value: number | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 60 && value <= 3_600 ? value : null;
}

function averagePace(elapsedSeconds: number, distanceMeters: number): number | null {
  if (!Number.isFinite(elapsedSeconds) || !Number.isFinite(distanceMeters) || distanceMeters < 50) return null;
  return usablePace(elapsedSeconds / (distanceMeters / 1_000));
}

function decimalDistance(value: number): string {
  return Math.max(0, value).toFixed(1).replace(/\.0$/, "");
}
