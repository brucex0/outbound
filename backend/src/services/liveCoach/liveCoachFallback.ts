import type { SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachMoment } from "./liveCoachTypes.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";

const messages: Record<SupportedAILocale, Record<LiveCoachMoment, { key: string; text: string }>> = {
  en: {
    progress: { key: "progress.steady", text: "Keep this pace and effort comfortable." },
    early_overpace: { key: "coach.early_settle", text: "Start a little slower; give yourself time to warm up." },
    pace_above_target: { key: "coach.ease_to_target", text: "Slow down gradually toward your target pace." },
    pace_below_target: { key: "coach.lift_to_target", text: "Speed up gradually toward your target pace." },
    pace_instability: { key: "coach.smooth_pace", text: "Adjust gradually toward your target pace, then hold it." },
    target_locked: { key: "progress.steady", text: "Keep this pace and effort comfortable." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "If it feels manageable, gradually return to your target pace." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Your pace is closer to the target now; keep the effort controlled." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "Slow to an easy jog; you should be able to speak a full sentence." },
    unexpected_stop: { key: "workout.pause", text: "Workout paused." },
    resume_after_break: { key: "workout.resume", text: "Workout resumed." },
    climb_start: { key: "coach.climb_by_effort", text: "Take shorter steps uphill and let your pace slow." },
    crest_recovery: { key: "coach.crest_reset", text: "The hill is easing; keep the effort easy before speeding up." },
    segment_transition: { key: "workout.segment_start", text: "New segment. Settle into the target before you press." },
    finish_opportunity: { key: "coach.strong_finish", text: "If you still feel comfortable, speed up gradually toward the finish." },
    race_start_restraint: { key: "coach.early_settle", text: "Start a little slower; give yourself time to warm up." },
    race_pace_locked: { key: "progress.steady", text: "Keep this pace and effort comfortable." },
    race_halfway_assessment: { key: "progress.halfway", text: "Halfway there. Stay patient and steady." },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "If it feels manageable, gradually return to your target pace." },
    race_late_strength: { key: "coach.strong_finish", text: "If you still feel comfortable, speed up gradually toward the finish." },
    race_final_kilometer: { key: "coach.strong_finish", text: "If you still feel comfortable, speed up gradually toward the finish." },
    challenge_start: { key: "challenge.start", text: "Challenge starts now. Build the pace smoothly." },
    challenge_complete: { key: "challenge.complete", text: "Challenge complete. Settle back into your run." },
    workout_instruction: { key: "workout.segment_start", text: "New segment. Settle into the target before you press." },
  },
  es: {
    progress: { key: "progress.steady", text: "Mantén este ritmo con un esfuerzo cómodo." },
    early_overpace: { key: "coach.early_settle", text: "Empieza un poco más despacio y date tiempo para calentar." },
    pace_above_target: { key: "coach.ease_to_target", text: "Baja poco a poco hasta el ritmo objetivo." },
    pace_below_target: { key: "coach.lift_to_target", text: "Acelera poco a poco hasta el ritmo objetivo." },
    pace_instability: { key: "coach.smooth_pace", text: "Acércate poco a poco al ritmo objetivo y mantenlo." },
    target_locked: { key: "progress.steady", text: "Mantén este ritmo con un esfuerzo cómodo." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "Si te resulta cómodo, vuelve poco a poco al ritmo objetivo." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Ahora estás más cerca del ritmo objetivo; mantén el esfuerzo controlado." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "Baja a un trote suave; deberías poder decir una frase completa." },
    unexpected_stop: { key: "workout.pause", text: "Entrenamiento en pausa." },
    resume_after_break: { key: "workout.resume", text: "Entrenamiento reanudado." },
    climb_start: { key: "coach.climb_by_effort", text: "Da pasos más cortos al subir y deja que baje el ritmo." },
    crest_recovery: { key: "coach.crest_reset", text: "La cuesta afloja; mantén un esfuerzo suave antes de acelerar." },
    segment_transition: { key: "workout.segment_start", text: "Nuevo segmento. Encuentra el objetivo antes de apretar." },
    finish_opportunity: { key: "coach.strong_finish", text: "Si aún te sientes cómodo, acelera poco a poco hasta el final." },
    race_start_restraint: { key: "coach.early_settle", text: "Empieza un poco más despacio y date tiempo para calentar." },
    race_pace_locked: { key: "progress.steady", text: "Mantén este ritmo con un esfuerzo cómodo." },
    race_halfway_assessment: { key: "progress.halfway", text: "Ya estás a mitad. Mantén la paciencia y la constancia." },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "Si te resulta cómodo, vuelve poco a poco al ritmo objetivo." },
    race_late_strength: { key: "coach.strong_finish", text: "Si aún te sientes cómodo, acelera poco a poco hasta el final." },
    race_final_kilometer: { key: "coach.strong_finish", text: "Si aún te sientes cómodo, acelera poco a poco hasta el final." },
    challenge_start: { key: "challenge.start", text: "Empieza el reto. Aumenta el ritmo con suavidad." },
    challenge_complete: { key: "challenge.complete", text: "Reto completado. Vuelve a tu ritmo de carrera." },
    workout_instruction: { key: "workout.segment_start", text: "Nuevo segmento. Encuentra el objetivo antes de apretar." },
  },
  "zh-Hans": {
    progress: { key: "progress.steady", text: "保持这个配速，强度以舒服为准。" },
    early_overpace: { key: "coach.early_settle", text: "起步稍慢一点，给身体时间热身。" },
    pace_above_target: { key: "coach.ease_to_target", text: "逐步放慢，回到目标配速。" },
    pace_below_target: { key: "coach.lift_to_target", text: "逐步加速，回到目标配速。" },
    pace_instability: { key: "coach.smooth_pace", text: "逐步调整到目标配速，然后保持。" },
    target_locked: { key: "progress.steady", text: "保持这个配速，强度以舒服为准。" },
    pace_drift: { key: "coach.rebuild_rhythm", text: "如果感觉还能轻松应对，就逐步回到目标配速。" },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "现在更接近目标配速了，继续控制强度。" },
    recovery_too_hard: { key: "coach.recovery_easy", text: "放慢到轻松慢跑，应该能说出一句完整的话。" },
    unexpected_stop: { key: "workout.pause", text: "训练已暂停。" },
    resume_after_break: { key: "workout.resume", text: "重启训练。" },
    climb_start: { key: "coach.climb_by_effort", text: "上坡时步子小一点，允许配速慢下来。" },
    crest_recovery: { key: "coach.crest_reset", text: "坡度缓下来了，先轻松跑一会儿，再考虑加速。" },
    segment_transition: { key: "workout.segment_start", text: "进入新阶段，先稳定到目标强度，再逐步发力。" },
    finish_opportunity: { key: "coach.strong_finish", text: "如果仍然感觉轻松，就逐步加速跑向终点。" },
    race_start_restraint: { key: "coach.early_settle", text: "起步稍慢一点，给身体时间热身。" },
    race_pace_locked: { key: "progress.steady", text: "保持这个配速，强度以舒服为准。" },
    race_halfway_assessment: { key: "progress.halfway", text: "已经过半，保持耐心和稳定。" },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "如果感觉还能轻松应对，就逐步回到目标配速。" },
    race_late_strength: { key: "coach.strong_finish", text: "如果仍然感觉轻松，就逐步加速跑向终点。" },
    race_final_kilometer: { key: "coach.strong_finish", text: "如果仍然感觉轻松，就逐步加速跑向终点。" },
    challenge_start: { key: "challenge.start", text: "挑战开始，平稳加速。" },
    challenge_complete: { key: "challenge.complete", text: "挑战完成，回到原来的跑步节奏。" },
    workout_instruction: { key: "workout.segment_start", text: "进入新阶段，先稳定到目标强度，再逐步发力。" },
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
