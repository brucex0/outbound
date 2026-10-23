import { createHash } from "node:crypto";
import type { LiveCoachLiveState, SupportedAILocale } from "../aiProviders/types.js";
import { fixedFallbackEnvelope } from "./liveCoachFallback.js";
import { validateLiveCoachOutput } from "./liveCoachOutputValidation.js";
import type { LiveCoachMoment } from "./liveCoachTypes.js";

const authoredVariants: Record<SupportedAILocale, Partial<Record<Exclude<LiveCoachMoment, "progress">, string[]>>> = {
  "en": {
    pace_instability: ["Your pace shifted outside the target range. Adjust gradually back to target."],
    pace_drift: ["You have slowed below your target pace. If comfortable, return to it gradually."],
    rhythm_recovery: ["You are closer to your target pace now. Hold it before adjusting again."],
    segment_transition: ["The next workout segment starts now. Adjust gradually to its prescribed effort."],
    finish_opportunity: ["The finish is near. If comfortable, build speed gradually and avoid sprinting."],
    challenge_start: ["Your challenge starts now. Increase pace gradually and keep the effort controlled."],
    challenge_complete: ["Your challenge is complete. Ease back to the pace you held before it."],
  },
  "es": {
    pace_instability: ["Tu ritmo ha cambiado y está fuera del objetivo. Vuelve a él poco a poco."],
    pace_drift: ["Has bajado del ritmo objetivo. Si te sientes cómodo, vuelve a él poco a poco."],
    rhythm_recovery: ["Ahora estás más cerca del ritmo objetivo. Mantenlo antes de volver a ajustar."],
    segment_transition: ["Empieza el siguiente tramo. Ajusta el esfuerzo poco a poco según lo indicado."],
    finish_opportunity: ["La meta está cerca. Si te sientes cómodo, acelera poco a poco, sin esprintar."],
    challenge_start: ["Tu reto empieza ahora. Acelera poco a poco y mantén el esfuerzo bajo control."],
    challenge_complete: ["Has completado el reto. Vuelve poco a poco al ritmo que llevabas antes."],
  },
  "zh-Hans": {
    pace_instability: ["配速变化后已偏离目标范围，逐步调整回目标配速。"],
    pace_drift: ["速度已降到目标配速以下，如果感觉轻松，就逐步恢复到目标配速。"],
    rhythm_recovery: ["现在更接近目标配速了，先保持住，不要急着再次调整。"],
    segment_transition: ["下一训练阶段开始了，按这一段的要求逐步调整强度。"],
    finish_opportunity: ["终点就在前面，如果感觉轻松，可以逐步加速，不要突然冲刺。"],
    challenge_start: ["挑战现在开始，逐步提速，保持强度可控。"],
    challenge_complete: ["挑战已完成，逐步回到挑战前的配速。"],
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
