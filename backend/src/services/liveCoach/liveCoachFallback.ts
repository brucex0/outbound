import type { SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachMoment } from "./liveCoachTypes.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";

const messages: Record<SupportedAILocale, Record<LiveCoachMoment, { key: string; text: string }>> = {
  en: {
    progress: { key: "progress.steady", text: "Keep this steady rhythm." },
    early_overpace: { key: "coach.settle", text: "Settle the effort and find a sustainable rhythm." },
    pace_above_target: { key: "coach.settle", text: "Settle the effort and find a sustainable rhythm." },
    pace_below_target: { key: "coach.restore_rhythm", text: "Relax your shoulders and gently find your rhythm again." },
    pace_instability: { key: "coach.restore_rhythm", text: "Relax your shoulders and gently find your rhythm again." },
    target_locked: { key: "progress.steady", text: "Keep this steady rhythm." },
    pace_drift: { key: "coach.restore_rhythm", text: "Relax your shoulders and gently find your rhythm again." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "That adjustment worked. You found the rhythm again." },
    recovery_too_hard: { key: "coach.settle", text: "Settle the effort and find a sustainable rhythm." },
    unexpected_stop: { key: "workout.pause", text: "Workout paused." },
    resume_after_break: { key: "workout.resume", text: "Workout resumed." },
    climb_start: { key: "coach.settle", text: "Settle the effort and find a sustainable rhythm." },
    crest_recovery: { key: "coach.rhythm_recovered", text: "That adjustment worked. You found the rhythm again." },
    segment_transition: { key: "workout.segment_start", text: "New segment. Settle into the target before you press." },
    finish_opportunity: { key: "coach.strong_finish", text: "Stay composed and let the effort rise gradually." },
    challenge_start: { key: "challenge.start", text: "Challenge starts now. Build the pace smoothly." },
    challenge_complete: { key: "challenge.complete", text: "Challenge complete. Settle back into your run." },
  },
  es: {
    progress: { key: "progress.steady", text: "Mantén este ritmo estable." },
    early_overpace: { key: "coach.settle", text: "Baja un poco el esfuerzo y encuentra un ritmo sostenible." },
    pace_above_target: { key: "coach.settle", text: "Baja un poco el esfuerzo y encuentra un ritmo sostenible." },
    pace_below_target: { key: "coach.restore_rhythm", text: "Relaja los hombros y recupera el ritmo poco a poco." },
    pace_instability: { key: "coach.restore_rhythm", text: "Relaja los hombros y recupera el ritmo poco a poco." },
    target_locked: { key: "progress.steady", text: "Mantén este ritmo estable." },
    pace_drift: { key: "coach.restore_rhythm", text: "Relaja los hombros y recupera el ritmo poco a poco." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Ese ajuste funcionó. Recuperaste el ritmo." },
    recovery_too_hard: { key: "coach.settle", text: "Baja un poco el esfuerzo y encuentra un ritmo sostenible." },
    unexpected_stop: { key: "workout.pause", text: "Entrenamiento en pausa." },
    resume_after_break: { key: "workout.resume", text: "Entrenamiento reanudado." },
    climb_start: { key: "coach.settle", text: "Baja un poco el esfuerzo y encuentra un ritmo sostenible." },
    crest_recovery: { key: "coach.rhythm_recovered", text: "Ese ajuste funcionó. Recuperaste el ritmo." },
    segment_transition: { key: "workout.segment_start", text: "Nuevo segmento. Encuentra el objetivo antes de apretar." },
    finish_opportunity: { key: "coach.strong_finish", text: "Mantén la calma y aumenta el esfuerzo gradualmente." },
    challenge_start: { key: "challenge.start", text: "Empieza el reto. Aumenta el ritmo con suavidad." },
    challenge_complete: { key: "challenge.complete", text: "Reto completado. Vuelve a tu ritmo de carrera." },
  },
  "zh-Hans": {
    progress: { key: "progress.steady", text: "保持现在的稳定节奏。" },
    early_overpace: { key: "coach.settle", text: "稍微收住强度，找到可持续的节奏。" },
    pace_above_target: { key: "coach.settle", text: "稍微收住强度，找到可持续的节奏。" },
    pace_below_target: { key: "coach.restore_rhythm", text: "放松肩膀，慢慢找回刚才的节奏。" },
    pace_instability: { key: "coach.restore_rhythm", text: "放松肩膀，慢慢找回刚才的节奏。" },
    target_locked: { key: "progress.steady", text: "保持现在的稳定节奏。" },
    pace_drift: { key: "coach.restore_rhythm", text: "放松肩膀，慢慢找回刚才的节奏。" },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "调整有效，你已经找回节奏了。" },
    recovery_too_hard: { key: "coach.settle", text: "稍微收住强度，找到可持续的节奏。" },
    unexpected_stop: { key: "workout.pause", text: "训练已暂停。" },
    resume_after_break: { key: "workout.resume", text: "重启训练。" },
    climb_start: { key: "coach.settle", text: "稍微收住强度，找到可持续的节奏。" },
    crest_recovery: { key: "coach.rhythm_recovered", text: "调整有效，你已经找回节奏了。" },
    segment_transition: { key: "workout.segment_start", text: "进入新阶段，先稳定到目标强度，再逐步发力。" },
    finish_opportunity: { key: "coach.strong_finish", text: "保持从容，逐步提升强度。" },
    challenge_start: { key: "challenge.start", text: "挑战开始，平稳加速。" },
    challenge_complete: { key: "challenge.complete", text: "挑战完成，回到原来的跑步节奏。" },
  },
};

export function fixedFallbackEnvelope(input: {
  cueRequestId: string;
  moment: LiveCoachMoment;
  locale: SupportedAILocale;
  validForMilliseconds: number;
  result: LiveCoachCueResult;
  source?: "fixed_pack" | "cached_fallback";
}): LiveCoachCueEnvelope {
  const now = new Date();
  const fallback = messages[input.locale][input.moment];
  return {
    contractVersion: 1,
    cueRequestId: input.cueRequestId,
    source: input.source ?? "cached_fallback",
    result: input.result,
    moment: input.moment,
    urgency: urgencyForMoment(input.moment),
    transcript: fallback.text,
    fixedCueKey: fallback.key,
    generatedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + input.validForMilliseconds).toISOString(),
  };
}
