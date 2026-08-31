import type { LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import type { LiveCoachMoment, RequestLiveCoachCueInput } from "./liveCoachTypes.js";

const dynamicMoments = new Set<LiveCoachMoment>([
  "progress",
  "early_overpace",
  "pace_above_target",
  "pace_below_target",
  "pace_instability",
  "target_locked",
  "pace_drift",
  "rhythm_recovery",
  "recovery_too_hard",
  "unexpected_stop",
  "resume_after_break",
  "climb_start",
  "crest_recovery",
  "segment_transition",
  "finish_opportunity",
  "challenge_start",
  "challenge_complete",
]);

export function cuePolicyDecision(input: RequestLiveCoachCueInput, config: LiveCoachFeatureConfig): {
  dynamicEligible: boolean;
  result?: "stale" | "invalid";
} {
  if (input.validForMilliseconds > config.cueValidityMilliseconds) return { dynamicEligible: false, result: "invalid" };
  if (input.liveState.elapsedSeconds - input.detectedAtElapsedSeconds > 10) return { dynamicEligible: false, result: "stale" };
  if (input.liveState.routeGuidanceActive) return { dynamicEligible: false };
  return { dynamicEligible: dynamicMoments.has(input.moment) };
}

export function urgencyForMoment(moment: LiveCoachMoment): "steady" | "opportunity" | "caution" {
  switch (moment) {
    case "progress":
      return "steady";
    case "early_overpace":
    case "pace_above_target":
    case "pace_below_target":
    case "pace_instability":
    case "pace_drift":
    case "recovery_too_hard":
    case "climb_start":
    case "crest_recovery":
    case "finish_opportunity":
    case "segment_transition":
    case "challenge_start":
      return "opportunity";
    default:
      return "steady";
  }
}
