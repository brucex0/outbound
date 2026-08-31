import type { SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachMoment } from "./liveCoachTypes.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";

const messages: Record<SupportedAILocale, Record<LiveCoachMoment, { key: string; text: string }>> = {
  en: {
    progress: { key: "progress.steady", text: "Keep this steady rhythm." },
    early_overpace: { key: "coach.early_settle", text: "Ease off a touch. Let your body settle into the run." },
    pace_above_target: { key: "coach.ease_to_target", text: "You're running faster than the target. Ease the pace down gradually." },
    pace_below_target: { key: "coach.lift_to_target", text: "You're running slower than the target. Lift the pace gradually and stay relaxed." },
    pace_instability: { key: "coach.smooth_pace", text: "Smooth the effort. Let the pace settle before you adjust again." },
    target_locked: { key: "progress.steady", text: "Keep this steady rhythm." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "Reset your posture and gently bring the rhythm back." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "That adjustment worked. You found the rhythm again." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "Make this recovery easy. Let your breathing and legs settle." },
    unexpected_stop: { key: "workout.pause", text: "Workout paused." },
    resume_after_break: { key: "workout.resume", text: "Workout resumed." },
    climb_start: { key: "coach.climb_by_effort", text: "Shorten your stride and run the climb by effort, not pace." },
    crest_recovery: { key: "coach.crest_reset", text: "The climb is easing. Reset your form before you build again." },
    segment_transition: { key: "workout.segment_start", text: "New segment. Settle into the target before you press." },
    finish_opportunity: { key: "coach.strong_finish", text: "Stay composed and let the effort rise gradually." },
    challenge_start: { key: "challenge.start", text: "Challenge starts now. Build the pace smoothly." },
    challenge_complete: { key: "challenge.complete", text: "Challenge complete. Settle back into your run." },
  },
  es: {
    progress: { key: "progress.steady", text: "Mantén este ritmo estable." },
    early_overpace: { key: "coach.early_settle", text: "Afloja un poco y entra en ritmo sin prisas." },
    pace_above_target: { key: "coach.ease_to_target", text: "Vas más rápido que el ritmo objetivo. Baja gradualmente y mantén el control." },
    pace_below_target: { key: "coach.lift_to_target", text: "Vas más lento que el ritmo objetivo. Aumenta poco a poco sin perder la relajación." },
    pace_instability: { key: "coach.smooth_pace", text: "Suaviza el esfuerzo. Deja que el ritmo se estabilice antes de volver a ajustarlo." },
    target_locked: { key: "progress.steady", text: "Mantén este ritmo estable." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "Recoloca la postura y recupera el ritmo poco a poco." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Ese ajuste funcionó. Recuperaste el ritmo." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "Haz que esta recuperación sea suave. Deja que se calmen la respiración y las piernas." },
    unexpected_stop: { key: "workout.pause", text: "Entrenamiento en pausa." },
    resume_after_break: { key: "workout.resume", text: "Entrenamiento reanudado." },
    climb_start: { key: "coach.climb_by_effort", text: "Acorta la zancada y sube por sensaciones, no por ritmo." },
    crest_recovery: { key: "coach.crest_reset", text: "La subida afloja. Recompón la postura antes de volver a apretar." },
    segment_transition: { key: "workout.segment_start", text: "Nuevo segmento. Encuentra el objetivo antes de apretar." },
    finish_opportunity: { key: "coach.strong_finish", text: "Mantén la calma y aumenta el esfuerzo gradualmente." },
    challenge_start: { key: "challenge.start", text: "Empieza el reto. Aumenta el ritmo con suavidad." },
    challenge_complete: { key: "challenge.complete", text: "Reto completado. Vuelve a tu ritmo de carrera." },
  },
  "zh-Hans": {
    progress: { key: "progress.steady", text: "保持现在的稳定节奏。" },
    early_overpace: { key: "coach.early_settle", text: "稍微收一点，别着急，让身体慢慢进入节奏。" },
    pace_above_target: { key: "coach.ease_to_target", text: "现在快于目标配速，逐步放慢，保持从容。" },
    pace_below_target: { key: "coach.lift_to_target", text: "现在慢于目标配速，放松地逐步提速。" },
    pace_instability: { key: "coach.smooth_pace", text: "先稳住强度，让配速稳定下来再调整。" },
    target_locked: { key: "progress.steady", text: "保持现在的稳定节奏。" },
    pace_drift: { key: "coach.rebuild_rhythm", text: "调整一下跑姿，放松地把节奏带回来。" },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "调整有效，你已经找回节奏了。" },
    recovery_too_hard: { key: "coach.recovery_easy", text: "恢复段再轻松一点，让呼吸和双腿缓下来。" },
    unexpected_stop: { key: "workout.pause", text: "训练已暂停。" },
    resume_after_break: { key: "workout.resume", text: "重启训练。" },
    climb_start: { key: "coach.climb_by_effort", text: "上坡缩短步幅，按体感控制强度，别追配速。" },
    crest_recovery: { key: "coach.crest_reset", text: "坡度缓下来了，先调整跑姿，再逐步发力。" },
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
