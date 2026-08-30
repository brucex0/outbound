import type { SupportedAILocale } from "../aiProviders/types.js";
import type { LiveCoachCueEnvelope, LiveCoachCueResult, LiveCoachMoment } from "./liveCoachTypes.js";
import { urgencyForMoment } from "./liveCoachCuePolicy.js";

const messages: Record<SupportedAILocale, Record<LiveCoachMoment, { key: string; text: string }>> = {
  en: {
    progress: { key: "progress.steady", text: "Keep the effort smooth and steady." },
    fast_start: { key: "coach.settle", text: "Settle the effort and find a sustainable rhythm." },
    pace_drift: { key: "coach.restore_rhythm", text: "Relax your shoulders and gently find your rhythm again." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "That adjustment worked. You found the rhythm again." },
    segment_transition: { key: "workout.segment_start", text: "New segment. Settle into the target before you press." },
    finish_opportunity: { key: "coach.strong_finish", text: "Stay composed and let the effort rise gradually." },
    challenge_start: { key: "challenge.start", text: "Challenge starts now. Build the pace smoothly." },
    challenge_complete: { key: "challenge.complete", text: "Challenge complete. Settle back into your run." },
  },
  es: {
    progress: { key: "progress.steady", text: "Mantén un esfuerzo fluido y constante." },
    fast_start: { key: "coach.settle", text: "Baja un poco el esfuerzo y encuentra un ritmo sostenible." },
    pace_drift: { key: "coach.restore_rhythm", text: "Relaja los hombros y recupera el ritmo poco a poco." },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "Ese ajuste funcionó. Recuperaste el ritmo." },
    segment_transition: { key: "workout.segment_start", text: "Nuevo segmento. Encuentra el objetivo antes de apretar." },
    finish_opportunity: { key: "coach.strong_finish", text: "Mantén la calma y aumenta el esfuerzo gradualmente." },
    challenge_start: { key: "challenge.start", text: "Empieza el reto. Aumenta el ritmo con suavidad." },
    challenge_complete: { key: "challenge.complete", text: "Reto completado. Vuelve a tu ritmo de carrera." },
  },
  "zh-Hans": {
    progress: { key: "progress.steady", text: "保持顺畅稳定的强度。" },
    fast_start: { key: "coach.settle", text: "稍微收住强度，找到可持续的节奏。" },
    pace_drift: { key: "coach.restore_rhythm", text: "放松肩膀，慢慢找回刚才的节奏。" },
    rhythm_recovery: { key: "coach.rhythm_recovered", text: "刚才的调整有效，你已经找回节奏了。" },
    segment_transition: { key: "workout.segment_start", text: "进入新阶段，先稳定到目标强度，再逐步发力。" },
    finish_opportunity: { key: "coach.strong_finish", text: "保持从容，让强度逐步提升。" },
    challenge_start: { key: "challenge.start", text: "挑战开始，平稳地提起速度。" },
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
