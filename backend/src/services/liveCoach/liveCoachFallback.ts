import type { SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachMoment } from "./liveCoachTypes.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";

const messages: Record<SupportedAILocale, Record<LiveCoachMoment, { key: string; text: string }>> = {
  en: {
    progress: { key: "progress.steady", text: "You are holding your target pace. Keep it steady." },
    early_overpace: { key: "coach.early_settle", text: "You are starting faster than your target. Slow down gradually to avoid an opening surge." },
    pace_above_target: { key: "coach.ease_to_target", text: "You are above your target pace. Slow down gradually to return to it." },
    pace_below_target: { key: "coach.lift_to_target", text: "You are below your target pace. Speed up gradually without an abrupt surge." },
    pace_instability: { key: "coach.smooth_pace", text: "Your pace shifted outside the target range. Adjust gradually back to target." },
    target_locked: { key: "progress.steady", text: "You are holding your target pace. Keep it steady." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "You have slowed below your target pace. If comfortable, return to it gradually." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "You are closer to your target pace now. Hold it before adjusting again." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "You are moving faster than this easy segment calls for. Slow to a conversational effort." },
    unexpected_stop: { key: "workout.pause", text: "Workout paused." },
    resume_after_break: { key: "workout.resume", text: "Workout resumed." },
    climb_start: { key: "coach.climb_by_effort", text: "You are on a climb. Shorten your steps and let your pace slow." },
    crest_recovery: { key: "coach.crest_reset", text: "The climb is easing. Keep effort easy before gradually increasing speed." },
    segment_transition: { key: "workout.segment_start", text: "The next workout segment starts now. Adjust gradually to its prescribed effort." },
    finish_opportunity: { key: "coach.strong_finish", text: "The finish is near. If comfortable, build speed gradually and avoid sprinting." },
    race_start_restraint: { key: "race.start_restraint", text: "Start the race at a controlled pace. Save a speed increase for later." },
    race_pace_locked: { key: "progress.steady", text: "You are holding your target pace. Keep it steady." },
    race_halfway_assessment: { key: "progress.halfway", text: "You are halfway to your goal." },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "You have slowed below your target pace. If comfortable, return to it gradually." },
    race_late_strength: { key: "coach.strong_finish", text: "The finish is near. If comfortable, build speed gradually and avoid sprinting." },
    race_final_kilometer: { key: "coach.strong_finish", text: "The finish is near. If comfortable, build speed gradually and avoid sprinting." },
    challenge_start: { key: "challenge.start", text: "Your challenge starts now. Increase pace gradually and keep the effort controlled." },
    challenge_complete: { key: "challenge.complete", text: "Your challenge is complete. Ease back to the pace you held before it." },
    workout_instruction: { key: "workout.segment_start", text: "The next workout segment starts now. Adjust gradually to its prescribed effort." },
  },
  es: {
    progress: { key: "progress.steady", text: "Estás manteniendo el ritmo objetivo. Sigue a ese ritmo." },
    early_overpace: { key: "coach.early_settle", text: "Has empezado por encima del ritmo objetivo. Baja la velocidad poco a poco, sin cambios bruscos." },
    pace_above_target: { key: "coach.ease_to_target", text: "Vas por encima del ritmo objetivo. Baja la velocidad poco a poco hasta recuperarlo." },
    pace_below_target: { key: "coach.lift_to_target", text: "Vas por debajo del ritmo objetivo. Acelera poco a poco, sin un cambio brusco." },
    pace_instability: { key: "coach.smooth_pace", text: "Tu ritmo ha cambiado y está fuera del objetivo. Vuelve a él poco a poco." },
    target_locked: { key: "progress.steady", text: "Estás manteniendo el ritmo objetivo. Sigue a ese ritmo." },
    pace_drift: { key: "coach.rebuild_rhythm", text: "Has bajado del ritmo objetivo. Si te sientes cómodo, vuelve a él poco a poco." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Ahora estás más cerca del ritmo objetivo. Mantenlo antes de volver a ajustar." },
    recovery_too_hard: { key: "coach.recovery_easy", text: "Vas más rápido de lo indicado para este tramo suave. Baja a un esfuerzo que te permita conversar." },
    unexpected_stop: { key: "workout.pause", text: "Entrenamiento en pausa." },
    resume_after_break: { key: "workout.resume", text: "Entrenamiento reanudado." },
    climb_start: { key: "coach.climb_by_effort", text: "Estás en una subida. Acorta los pasos y deja que baje la velocidad." },
    crest_recovery: { key: "coach.crest_reset", text: "La subida está aflojando. Mantén un esfuerzo suave antes de acelerar poco a poco." },
    segment_transition: { key: "workout.segment_start", text: "Empieza el siguiente tramo. Ajusta el esfuerzo poco a poco según lo indicado." },
    finish_opportunity: { key: "coach.strong_finish", text: "La meta está cerca. Si te sientes cómodo, acelera poco a poco, sin esprintar." },
    race_start_restraint: { key: "race.start_restraint", text: "Empieza la carrera a un ritmo controlado. Deja los aumentos de velocidad para más adelante." },
    race_pace_locked: { key: "progress.steady", text: "Estás manteniendo el ritmo objetivo. Sigue a ese ritmo." },
    race_halfway_assessment: { key: "progress.halfway", text: "Has llegado a la mitad de tu objetivo." },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "Has bajado del ritmo objetivo. Si te sientes cómodo, vuelve a él poco a poco." },
    race_late_strength: { key: "coach.strong_finish", text: "La meta está cerca. Si te sientes cómodo, acelera poco a poco, sin esprintar." },
    race_final_kilometer: { key: "coach.strong_finish", text: "La meta está cerca. Si te sientes cómodo, acelera poco a poco, sin esprintar." },
    challenge_start: { key: "challenge.start", text: "Tu reto empieza ahora. Acelera poco a poco y mantén el esfuerzo bajo control." },
    challenge_complete: { key: "challenge.complete", text: "Has completado el reto. Vuelve poco a poco al ritmo que llevabas antes." },
    workout_instruction: { key: "workout.segment_start", text: "Empieza el siguiente tramo. Ajusta el esfuerzo poco a poco según lo indicado." },
  },
  "zh-Hans": {
    progress: { key: "progress.steady", text: "你正保持在目标配速，继续稳住这个速度。" },
    early_overpace: { key: "coach.early_settle", text: "起步已快于目标配速，逐步放慢，不要在开头猛冲。" },
    pace_above_target: { key: "coach.ease_to_target", text: "当前速度高于目标配速，逐步放慢，回到目标范围。" },
    pace_below_target: { key: "coach.lift_to_target", text: "当前速度低于目标配速，慢慢提速，不要突然加速。" },
    pace_instability: { key: "coach.smooth_pace", text: "配速变化后已偏离目标范围，逐步调整回目标配速。" },
    target_locked: { key: "progress.steady", text: "你正保持在目标配速，继续稳住这个速度。" },
    pace_drift: { key: "coach.rebuild_rhythm", text: "速度已降到目标配速以下，如果感觉轻松，就逐步恢复到目标配速。" },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "现在更接近目标配速了，先保持住，不要急着再次调整。" },
    recovery_too_hard: { key: "coach.recovery_easy", text: "这一段快于目标配速，请放慢到能轻松交谈的强度。" },
    unexpected_stop: { key: "workout.pause", text: "训练已暂停。" },
    resume_after_break: { key: "workout.resume", text: "训练已恢复。" },
    climb_start: { key: "coach.climb_by_effort", text: "现在正在上坡，步子小一点，允许速度慢下来。" },
    crest_recovery: { key: "coach.crest_reset", text: "坡度缓下来了，先保持轻松，再考虑逐步提速。" },
    segment_transition: { key: "workout.segment_start", text: "下一训练阶段开始了，按这一段的要求逐步调整强度。" },
    finish_opportunity: { key: "coach.strong_finish", text: "终点就在前面，如果感觉轻松，可以逐步加速，不要突然冲刺。" },
    race_start_restraint: { key: "race.start_restraint", text: "比赛刚开始，先控制好配速，留到后面再考虑提速。" },
    race_pace_locked: { key: "progress.steady", text: "你正保持在目标配速，继续稳住这个速度。" },
    race_halfway_assessment: { key: "progress.halfway", text: "目标已完成一半。" },
    race_late_fade: { key: "coach.rebuild_rhythm", text: "速度已降到目标配速以下，如果感觉轻松，就逐步恢复到目标配速。" },
    race_late_strength: { key: "coach.strong_finish", text: "终点就在前面，如果感觉轻松，可以逐步加速，不要突然冲刺。" },
    race_final_kilometer: { key: "coach.strong_finish", text: "终点就在前面，如果感觉轻松，可以逐步加速，不要突然冲刺。" },
    challenge_start: { key: "challenge.start", text: "挑战现在开始，逐步提速，保持强度可控。" },
    challenge_complete: { key: "challenge.complete", text: "挑战已完成，逐步回到挑战前的配速。" },
    workout_instruction: { key: "workout.segment_start", text: "下一训练阶段开始了，按这一段的要求逐步调整强度。" },
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
    transcript: input.moment === "progress" ? "" : fallback.text,
    fixedCueKey: input.moment === "progress" ? undefined : fallback.key,
    generatedAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + input.validForMilliseconds).toISOString(),
  };
}
