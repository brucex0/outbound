import { generateAssistantReply } from "../services/ai.js";
import { generateLiveCoachGuidancePlan } from "../services/liveCoach/liveCoachGuidancePlanner.js";
import { loadLiveCoachFeatureConfig } from "../services/liveCoach/liveCoachFeatureConfig.js";
import { standaloneWorkoutCatalog } from "../data/standaloneWorkouts.js";
import type { LiveCoachCompiledContext } from "../services/aiProviders/types.js";
import { aiFailure } from "../services/aiReliability/structuredGeneration.js";

// Synthetic fixtures only. Run as a Cloud Run job with the API runtime identity.
const mode = process.env.AI_RELIABILITY_MODE === "failover" ? "failover" : "raw";
process.env.AI_RELIABILITY_BENCHMARK = mode === "raw" ? "true" : "false";
process.env.AI_FALLBACK_VALIDATED = mode === "failover" ? "true" : "false";
// A deliberately nonexistent model exercises live alternate validation without
// changing production routing or simulating successful provider responses.
const models = (mode === "failover" ? "gemini-0.0-unavailable" : process.env.AI_RELIABILITY_MODELS || "gemini-3.8-flash,gemini-3.6-flash").split(",");
const operations = (process.env.AI_RELIABILITY_OPERATIONS || "assistant,live_coach").split(",");
if (!operations.length || operations.some((operation) => !["assistant", "live_coach"].includes(operation))) {
  throw new Error("AI_RELIABILITY_OPERATIONS must contain assistant and/or live_coach");
}
const rounds = Math.min(10, Math.max(1, Number(process.env.AI_RELIABILITY_ROUNDS || (mode === "failover" ? 1 : 3))));
if (!Number.isInteger(rounds)) throw new Error("AI_RELIABILITY_ROUNDS must be an integer");
const workout = standaloneWorkoutCatalog.workouts.find((item) => item.id === "standalone-guided-half-marathon")!;
const instructions = workout.guideInstructions!;
const samples: Array<{model: string; operation: string; locale: string; success: boolean; elapsed_ms: number}> = [];
for (let round = 0; round < rounds; round++) {
  for (const locale of ["en", "zh-Hans", "es"] as const) {
    for (const operation of operations) {
      for (const model of models) {
        process.env.APP_AI_MODEL = model;
        const start = Date.now();
        let success = false;
        let category: string | undefined;
        try {
          if (operation === "assistant") {
            const reply = await generateAssistantReply({
              prompt: "Where can I find my saved activities? Give a practical next step without inventing runner history.",
              capability: "support", context: { guideName: "supportive", activityCount: 0, weeklyDistanceKilometers: 0 }, messages: [], locale,
            });
            success = reply.trim().length > 0;
          } else {
            const context: LiveCoachCompiledContext = {
              version: 4, measurementUnitSystem: "metric", runnerModelVersion: "synthetic-empty", locale,
              activityType: "running", goalType: "distance", race: null,
              bio: { biography: null, ageYears: null, sexAtBirth: null, heightCentimeters: null, weightKilograms: null,
                goalSummary: null, scheduleSummary: null, comfortableDurationMinutes: null, recentSessionsPerWeek: null,
                targetSessionsPerWeek: null, preferredLongRunDay: null, guidanceDetail: null, primaryMotivation: null,
                preferredRunGoalType: null, constraints: null },
              coachingProfile: { fitnessLevel: null, weeklyVolumeKilometers: null, preferredPaceSecondsPerKilometer: null,
                strengths: [], weaknesses: [], goals: null, records: null, recentMemorySummary: null },
              workout: null, clientWorkout: null, readiness: null, surveySummary: [], runnerInsights: [], runnerBeliefs: [],
              recentTraining: { sevenDayActivities: [], sevenDaySummary: null, twentyEightDaySummary: null, recentWorkoutFeedback: [] },
              environment: { timeZoneIdentifier: "America/Los_Angeles", indoor: false, approximateLocation: null, weather: null },
              guidancePriorities: [], cuePreferences: [], safetyRequiresFixedOnly: false,
              workoutExecution: { source: "standalone_catalog", id: workout.id, catalogVersion: standaloneWorkoutCatalog.version,
                title: workout.title, targetDistanceMeters: workout.targetDistanceMeters ?? null, targetDurationSeconds: null,
                ...instructions, segments: instructions.segments.map((segment) => ({ ...segment, referenceCue: segment.cue, adjustmentCue: segment.fallback })) },
            };
            const config = loadLiveCoachFeatureConfig();
            config.planner = { ...config.planner, enabled: true, model, deadlineMilliseconds: 45_000 };
            const result = await generateLiveCoachGuidancePlan(context, "plainstride_supportive_v1", config);
            success = result.status === "generated" && result.plan.cues.filter((cue) => cue.moment === "workout_instruction").length === instructions.segments.length;
          }
        } catch (error) { category = aiFailure(error).category; }
        const sample = { model, operation, locale, success, elapsed_ms: Date.now() - start };
        samples.push(sample);
        console.info(JSON.stringify({ event: "ai_reliability_sample", mode, round, ...sample, category }));
        await new Promise((resolve) => setTimeout(resolve, 3_000));
      }
    }
  }
}
for (const model of models) {
  for (const operation of operations) {
    const group = samples.filter((sample) => sample.model === model && sample.operation === operation);
    const durations = group.filter((sample) => sample.success).map((sample) => sample.elapsed_ms).sort((a, b) => a - b);
    const percentile = (p: number) => durations.length ? durations[Math.ceil(durations.length * p) - 1] : null;
    const p95 = percentile(0.95);
    const latencyLimit = mode === "raw" ? operation === "assistant" ? 8_000 : 25_000 : operation === "assistant" ? 20_000 : 45_000;
    const passed = durations.length / group.length >= 0.95 && p95 !== null && p95 <= latencyLimit
      && ["en", "zh-Hans", "es"].every((locale) => group.some((sample) => sample.locale === locale && sample.success));
    if (!passed) process.exitCode = 1;
    console.info(JSON.stringify({ event: "ai_reliability_summary", mode, model, operation, samples: group.length,
      successes: durations.length, success_rate: durations.length / group.length, p50_ms: percentile(0.5), p95_ms: p95, passed }));
  }
}
