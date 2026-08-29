import type { LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";
import type { LiveCoachMoment, RequestLiveCoachCueInput } from "./liveCoachTypes.js";

const dynamicMoments = new Set<LiveCoachMoment>(["fast_start", "pace_drift", "finish_opportunity"]);

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
    case "fast_start":
    case "pace_drift":
    case "finish_opportunity":
    case "segment_transition":
    case "challenge_start":
      return "opportunity";
    default:
      return "steady";
  }
}
