import { findVoiceProfile } from "./liveCoachCatalog.js";
import type { VoiceProfileId } from "../aiProviders/types.js";

type CueDeliveryContext = {
  situation: string;
  delivery: string;
};

const CUE_DELIVERY_CONTEXT: Record<string, CueDeliveryContext> = {
  "countdown.three": {
    situation: "The first beat of a three-two-one workout start countdown.",
    delivery: "Crisp and compact, with controlled anticipation and the same cadence as the next two numbers.",
  },
  "countdown.two": {
    situation: "The middle beat of a three-two-one workout start countdown.",
    delivery: "Crisp and compact, maintaining an even countdown cadence without stretching the word.",
  },
  "countdown.one": {
    situation: "The final beat immediately before the workout starts.",
    delivery: "Crisp and compact, with a small lift of anticipation but no theatrical emphasis.",
  },
  "countdown.go": {
    situation: "The immediate command that starts the workout after a countdown.",
    delivery: "Decisive, energetic, and very brief. Make it motivating without shouting or sounding dramatic.",
  },
  "workout.pause": {
    situation: "Confirmation that the runner has paused the workout.",
    delivery: "Clear and matter-of-fact, with calm confirmation rather than celebration or concern.",
  },
  "workout.resume": {
    situation: "Confirmation that the runner has resumed a paused workout.",
    delivery: "Clear, forward-moving, and lightly positive, without making it sound like a new countdown.",
  },
  "workout.segment_start": {
    situation: "A new structured workout segment has just begun.",
    delivery: "Alert and instructional. Give the transition first, then the pacing advice with grounded confidence.",
  },
  "workout.complete": {
    situation: "The structured workout has ended and the runner should ease down.",
    delivery: "Warmly conclusive and satisfying, then softer and calmer on the recovery instruction. Avoid hype.",
  },
  "route.advisory": {
    situation: "A non-urgent route update is available while the runner is moving.",
    delivery: "Informational, calm, and easy to catch outdoors. Do not imply danger or urgency.",
  },
  "route.caution": {
    situation: "A route condition needs the runner's immediate attention for safety.",
    delivery: "Firm and clearly urgent enough to interrupt attention, but controlled and never alarmist.",
  },
  "route.wrong_way": {
    situation: "The runner may have left the selected route and needs to verify direction.",
    delivery: "Direct, calm, and nonjudgmental. Emphasize slowing down and checking safely, not the mistake.",
  },
  "route.rejoin": {
    situation: "The runner has returned to the selected route.",
    delivery: "Reassuring confirmation with a modest positive lift, then settle naturally.",
  },
  "route.arrival": {
    situation: "The runner has reached the selected route's endpoint.",
    delivery: "Clear and gently positive, with a natural sense of completion rather than a race-finish celebration.",
  },
  "progress.one_third": {
    situation: "The runner has completed the first third of the current effort.",
    delivery: "Positive but patient. Mark the milestone briefly, then make the steadying advice feel sustainable.",
  },
  "progress.halfway": {
    situation: "The runner has reached the halfway point of the current effort.",
    delivery: "Encouraging and composed. Acknowledge progress without implying the runner should accelerate.",
  },
  "progress.two_thirds": {
    situation: "The runner has completed two thirds of the current effort.",
    delivery: "Quietly motivating and controlled, keeping the focus on composure rather than urgency.",
  },
  "progress.finish_soon": {
    situation: "The end of the current effort is approaching.",
    delivery: "Add a restrained motivational lift while preserving calm, sustainable effort. Do not shout.",
  },
  "progress.steady": {
    situation: "The runner is on target and should maintain the current rhythm.",
    delivery: "Reassuring, even, and low-pressure, as confirmation rather than correction.",
  },
  "coach.early_settle": {
    situation: "The runner's opening pace is persistently faster than their personalized sustainable target.",
    delivery: "Patient and calming. Make the small early adjustment feel preventative, easy, and free of criticism.",
  },
  "coach.ease_to_target": {
    situation: "The runner is moving faster than the active workout target and should gradually return to its range.",
    delivery: "Clear and measured, with gentle emphasis on gradual control rather than an abrupt slowdown.",
  },
  "coach.lift_to_target": {
    situation: "The runner is moving slower than the active workout target and can gradually return to its range.",
    delivery: "Encouraging and relaxed. Invite a controlled lift without urgency, strain, or judgment.",
  },
  "coach.smooth_pace": {
    situation: "The runner's recent pace is unusually variable and needs time to stabilize before another adjustment.",
    delivery: "Steady and grounding, with an unhurried pause after the first sentence. Do not sound corrective or impatient.",
  },
  "coach.rebuild_rhythm": {
    situation: "The runner has gradually slowed relative to their own earlier sustainable rhythm.",
    delivery: "Supportive and practical. Make the posture reset distinct, then guide the rhythm back without pressure.",
  },
  "coach.recovery_easy": {
    situation: "The runner is pushing a warmup, recovery, or cooldown segment harder than its intended easy effort.",
    delivery: "Soft, permissive, and visibly calmer than a work-interval cue. Make easing off feel purposeful.",
  },
  "coach.climb_by_effort": {
    situation: "The runner has entered a sustained climb where flat-ground pace is no longer the right effort guide.",
    delivery: "Practical and composed. Give the stride cue clearly, then emphasize effort over pace without sounding urgent.",
  },
  "coach.crest_reset": {
    situation: "A sustained climb has eased and the runner should reset form before increasing effort again.",
    delivery: "Reassuring and transitional. Let the first sentence release tension, then keep the rebuild advice patient.",
  },
  "coach.settle": {
    situation: "The runner should reduce strain and find a sustainable effort.",
    delivery: "Grounded, calming, and unhurried. Make the adjustment feel achievable, not like criticism.",
  },
  "coach.restore_rhythm": {
    situation: "The runner has lost smooth rhythm and needs a gentle physical reset.",
    delivery: "Supportive and soothing, with a natural pause between relaxing the shoulders and finding rhythm.",
  },
  "coach.rhythm_recovered": {
    situation: "The runner's recent adjustment worked and their rhythm has recovered.",
    delivery: "Warm validation with modest confidence. Avoid sounding surprised, exaggerated, or congratulatory.",
  },
  "coach.strong_finish": {
    situation: "The runner can build toward a strong but controlled finish.",
    delivery: "Motivating and purposeful, with energy rising slightly toward the end but no aggressive pressure.",
  },
  "challenge.start": {
    situation: "A timed or structured in-run challenge begins now.",
    delivery: "Clear kickoff energy followed by controlled pacing guidance. Motivating, not frantic.",
  },
  "challenge.complete": {
    situation: "An in-run challenge has ended and the runner should return to normal rhythm.",
    delivery: "Briefly celebratory, then noticeably calmer on the transition back into the run.",
  },
  "fallback.unavailable": {
    situation: "Personalized coaching is temporarily unavailable, so this safe fallback keeps the runner steady.",
    delivery: "Calm, neutral, and reassuring. Do not sound apologetic, technical, or concerned.",
  },
  "voice.preview": {
    situation: "A runner is previewing this voice before choosing it for live coaching.",
    delivery: "Natural and representative of an everyday coaching cue: friendly, clear, relaxed, and not performative.",
  },
};

export function fixedCueDeliveryInstructions(
  cueKey: string,
  voiceProfileId: VoiceProfileId,
  rejectionCorrection: string
): string {
  const cue = CUE_DELIVERY_CONTEXT[cueKey];
  if (!cue) throw new Error(`Fixed live-coach cue is missing delivery context: ${cueKey}.`);
  const voice = findVoiceProfile(voiceProfileId);
  if (!voice) throw new Error(`Unknown fixed live-coach voice profile: ${voiceProfileId}.`);
  return [
    `Situation: ${cue.situation}`,
    `Delivery intent: ${cue.delivery}`,
    `Product voice style: ${voice.localized.en.description}`,
    "Keep this baseline rendition compatible with Plainstride's supportive, focused, and calm coaching personas.",
    rejectionCorrection,
  ].filter(Boolean).join(" ");
}
