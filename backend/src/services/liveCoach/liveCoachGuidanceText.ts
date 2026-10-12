import { createHash } from "node:crypto";
import type { LiveCoachLiveState, SupportedAILocale } from "../aiProviders/types.js";
import { fixedFallbackEnvelope } from "./liveCoachFallback.js";
import { validateLiveCoachOutput } from "./liveCoachOutputValidation.js";
import type { LiveCoachMoment } from "./liveCoachTypes.js";

const authoredVariants: Record<SupportedAILocale, Partial<Record<Exclude<LiveCoachMoment, "progress">, string[]>>> = {
  en: {
    pace_instability: [
      "Adjust gradually toward your target pace, then hold it.",
    ],
    pace_drift: [
      "If it feels manageable, gradually return to your target pace.",
    ],
    rhythm_recovery: [
      "Your pace is closer to the target now; keep the effort controlled.",
    ],
    segment_transition: [
      "New segment. Settle into the target before adding pressure.",
      "The next segment starts now. Find control first, then build.",
    ],
    finish_opportunity: [
      "If you still feel comfortable, speed up gradually toward the finish.",
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
    pace_instability: [
      "Acércate poco a poco al ritmo objetivo y mantenlo.",
    ],
    pace_drift: [
      "Si te resulta cómodo, vuelve poco a poco al ritmo objetivo.",
    ],
    rhythm_recovery: [
      "Ahora estás más cerca del ritmo objetivo; mantén el esfuerzo controlado.",
    ],
    segment_transition: [
      "Nuevo segmento. Encuentra el objetivo antes de aumentar el esfuerzo.",
      "Empieza el siguiente segmento con control y aumenta después.",
    ],
    finish_opportunity: [
      "Si aún te sientes cómodo, acelera poco a poco hasta el final.",
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
    pace_instability: [
      "逐步调整到目标配速，然后保持。",
    ],
    pace_drift: [
      "如果感觉还能轻松应对，就逐步回到目标配速。",
    ],
    rhythm_recovery: [
      "现在更接近目标配速了，继续控制强度。",
    ],
    segment_transition: [
      "进入新阶段，先稳定到目标强度，再逐步发力。",
      "下一阶段开始，先保持控制，再慢慢提升。",
    ],
    finish_opportunity: [
      "如果仍然感觉轻松，就逐步加速跑向终点。",
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
  const variants = authoredVariants[input.locale][input.moment] ?? [fixedFallbackEnvelope({
    cueRequestId: input.cueRequestId,
    moment: input.moment,
    locale: input.locale,
    validForMilliseconds: 5_000,
    result: "success",
  }).transcript];
  const index = createHash("sha256").update(input.cueRequestId).digest().readUInt32BE(0) % variants.length;
  return validateLiveCoachOutput(variants[index]);
}

function progressTranscript(
  locale: SupportedAILocale,
  state: LiveCoachLiveState,
  unitSystem: "metric" | "imperial"
): string {
  if (state.remainingDistanceMeters != null) {
    return remainingDistanceTranscript(locale, state.remainingDistanceMeters, unitSystem);
  }
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

function remainingDistanceTranscript(
  locale: SupportedAILocale,
  remainingMeters: number,
  unitSystem: "metric" | "imperial"
): string {
  const distance = unitSystem === "imperial" ? remainingMeters / 1_609.344 : remainingMeters;
  const rounded = unitSystem === "imperial"
    ? Math.max(0.01, Math.round(distance * 100) / 100)
    : Math.max(1, Math.round(distance));
  if (locale === "zh-Hans") {
    return validateLiveCoachOutput(`还剩${rounded}${unitSystem === "imperial" ? "英里" : "米"}。`);
  }
  if (locale === "es") {
    const unit = unitSystem === "imperial" ? (rounded === 1 ? "milla" : "millas") : "metros";
    return validateLiveCoachOutput(`Quedan ${rounded} ${unit}.`);
  }
  const unit = unitSystem === "imperial" ? (rounded === 1 ? "mile" : "miles") : "meters";
  return validateLiveCoachOutput(`${rounded} ${unit} to go.`);
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
