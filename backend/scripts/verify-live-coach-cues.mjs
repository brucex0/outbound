import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fixedFallbackEnvelope } from "../dist/services/liveCoach/liveCoachFallback.js";
import { LIVE_COACH_MOMENTS } from "../dist/services/liveCoach/liveCoachTypes.js";
import { transcriptForLiveCoachCue } from "../dist/services/liveCoach/liveCoachGuidanceText.js";
import { fixedCueDeliveryInstructions } from "../dist/services/liveCoach/fixedCueDelivery.js";
import { generateLiveCoachGuidancePlan } from "../dist/services/liveCoach/liveCoachGuidancePlanner.js";
import { loadLiveCoachFeatureConfig } from "../dist/services/liveCoach/liveCoachFeatureConfig.js";

const catalog = JSON.parse(await readFile(new URL("../resources/liveCoachAudio/catalog.v1.json", import.meta.url)));
const byKey = new Map(catalog.entries.map(entry => [entry.cueKey, entry]));
const liveState = { elapsedSeconds: 600, distanceMeters: 2000, currentPaceSecondsPerKilometer: 300, rollingPaceSecondsPerKilometer: 300, routeGuidanceActive: false };
const config = loadLiveCoachFeatureConfig({ LIVE_COACH_PLANNER_ENABLED: "false" });
const localizations = JSON.parse(await readFile(new URL("../../ios/Outbound/Outbound/Localizable.xcstrings", import.meta.url))).strings;
const displayCueKeys = {
  "live_guidance.auto_pause": "workout.pause",
  "live_guidance.auto_resume": "workout.resume",
  "live_guidance.workout_complete": "workout.complete",
  "live_guidance.sudden_speed_increase": "coach.speed_increase",
  "live_guidance.sudden_speed_decrease": "coach.speed_decrease",
  "route.guidance.off_route": "route.off_route",
  "route.guidance.rejoined": "route.rejoin",
  "route.guidance.wrong_way": "route.wrong_way",
  "route.guidance.arrival": "route.arrival",
};
const androidRoot = new URL("../../android/feature/livecoach/src/main/", import.meta.url);
const kotlinKeys = await readFile(new URL("kotlin/com/plainstride/outbound/feature/livecoach/audio/LiveCoachAudio.kt", androidRoot), "utf8");
const kotlinPhrases = await readFile(new URL("kotlin/com/plainstride/outbound/feature/livecoach/audio/LocalizedFallbackPhrases.kt", androidRoot), "utf8");
function androidMomentMap(source, valuePattern) {
  const values = new Map();
  for (const line of source.split("\n")) {
    const value = line.match(valuePattern)?.[1];
    if (value) for (const match of line.matchAll(/LiveCoachMoment\.(\w+)/g)) values.set(match[1], value);
  }
  return values;
}
const androidKeys = androidMomentMap(kotlinKeys, /-> "([^"]+)"/);
const androidResources = androidMomentMap(kotlinPhrases, /-> R\.string\.(\w+)/);
let checks = 0;
for (const locale of ["en", "es", "zh-Hans"]) {
  const folder = locale === "en" ? "values" : locale === "es" ? "values-es" : "values-zh-rCN";
  const xml = await readFile(new URL(`res/${folder}/strings.xml`, androidRoot), "utf8");
  const strings = new Map([...xml.matchAll(/<string name="([^"]+)">([^<]*)<\/string>/g)].map(match => [match[1], match[2].replaceAll("\\'", "'").replaceAll("&amp;", "&")]));
  for (const [key, cueKey] of Object.entries(displayCueKeys)) {
    assert.equal(localizations[key].localizations[locale].stringUnit.value, byKey.get(cueKey).texts[locale], key + "/" + locale);
    checks++;
  }
  for (const entry of catalog.entries) {
    assert.ok(entry.texts[locale]);
    assert.doesNotMatch(entry.texts[locale], /find.*rhythm|stay composed|stay tall|keep stacking|nice work|keep it smooth|找回节奏|保持从容/i);
    for (const voice of ["plainstride_clear_1", "plainstride_warm_1"]) assert.ok(fixedCueDeliveryInstructions(entry.cueKey, voice, ""));
    checks++;
  }
  for (const moment of LIVE_COACH_MOMENTS) {
    const fallback = fixedFallbackEnvelope({ cueRequestId: "fixture", moment, locale, validForMilliseconds: 5000, result: "success" });
    if (moment === "progress") {
      assert.equal(fallback.transcript, "");
      assert.equal(fallback.fixedCueKey, undefined);
      assert.ok(transcriptForLiveCoachCue({ locale, moment, liveState, cueRequestId: "fixture", measurementUnitSystem: "metric" }).length > 0);
    } else {
      assert.equal(fallback.transcript, byKey.get(fallback.fixedCueKey)?.texts[locale], moment + "/" + locale);
      assert.equal(transcriptForLiveCoachCue({ locale, moment, liveState, cueRequestId: "fixture", measurementUnitSystem: "metric" }), fallback.transcript);
      const androidMoment = moment.split("_").map(word => word[0].toUpperCase() + word.slice(1)).join("");
      assert.equal(strings.get(androidResources.get(androidMoment)), byKey.get(androidKeys.get(androidMoment))?.texts[locale], "Android " + moment + "/" + locale);
      checks++;
    }
    checks++;
  }
  assert.equal(strings.get("live_coach_sudden_speed_increase"), byKey.get("coach.settle").texts[locale]);
  assert.equal(strings.get("live_coach_sudden_speed_decrease"), byKey.get("coach.restore_rhythm").texts[locale]);
  checks += 2;
  const segment = { id: "fixture-segment", trigger: { type: "elapsed_time", startSeconds: 0, endSeconds: 300 }, effort: { rpeMin: 3, rpeMax: 4, feel: "comfortable" }, referenceCue: "Begin at the prescribed easy effort.", instruction: "easy", adjustmentCue: "adjust gradually" };
  const context = { locale, measurementUnitSystem: "metric", activityType: "running", race: null, safetyRequiresFixedOnly: false, workout: null, clientWorkout: null, workoutExecution: { segments: [segment] } };
  const result = await generateLiveCoachGuidancePlan(context, "plainstride_supportive_v1", config);
  assert.equal(result.status, "fallback");
  assert.ok(result.plan.cues.every(cue => cue.phrases.every(phrase => phrase.text.length > 0)));
  assert.ok(!result.plan.cues.some(cue => cue.moment === "progress"));
  const instruction = result.plan.cues.find(cue => cue.instructionId === segment.id).phrases[0].text;
  if (locale !== "en") { assert.ok(instruction.includes("3")); assert.ok(instruction.includes("4")); }
  checks++;
}
console.log(`Verified ${catalog.entries.length} fixed cues, all locale/moment mappings, measured progress, and localized workout targets (${checks} checks).`);
