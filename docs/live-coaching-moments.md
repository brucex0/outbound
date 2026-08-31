# Live Coaching Moments

Open this when adding, tuning, suppressing, localizing, or analyzing a live coaching moment. This is the source of truth for the current definitions and the signal gates for future moments.

## Product Model

A coachable moment is not a sensor threshold by itself. The pipeline is:

```text
trusted signal + workout target + recent personal baseline + enough persistence
  -> semantic moment
  -> priority/cooldown decision
  -> dynamic wording or reviewed fixed cue
  -> optional outcome evaluation
```

The semantic moment says what happened. Audio wording may vary, but it must not change the workout, invent a target, diagnose a condition, or claim a sensor that was not supplied.

## Current Phone-Sensor Definitions

These values are implemented in `Guide/LiveGuidanceModels.swift`, `Guide/VirtualGuide.swift`, and the backend live-coach contract.

| Moment | Current definition | Signal and context | Frequency |
| --- | --- | --- | --- |
| `progress` | A factual progress or goal update is due. | Default every 3 active minutes or each 1 km/1 mi for running; goal milestones and reliable-distance gates can alter timing. | Existing progress cadence and speech-gap rules. |
| `early_overpace` | The first sustained running pace is faster than the active target or personal reference. | 30-second average, 75-240 active seconds, faster by the target's tolerance; suppressed on meaningful grade. | Once per session. |
| `pace_above_target` | Pace is persistently faster than a pace-enabled non-recovery workout segment. | At least 45 seconds into the segment; 30-second average exceeds the faster edge of its personalized pace band; suppressed on meaningful grade. | Once per segment. |
| `pace_below_target` | Pace is persistently slower than a segment that explicitly allows a lower-bound cue. | At least 45 seconds into the segment; 30-second average exceeds the slower edge; suppressed on meaningful grade. Warmup, recovery, and cooldown intentionally have no slower edge. | Once per segment. |
| `pace_instability` | Recent pace varies enough that a smoother rhythm is more useful than a faster/slower command. | Pace-enabled segment, 120 seconds into the segment, at least 8 valid samples over 90 seconds, 90th-to-10th percentile spread at least 60 s/km or 15% of target; suppressed on meaningful grade. | At most every 10 minutes. |
| `target_locked` | The runner has held a target accurately and smoothly long enough to reinforce it. | Segment opts in; at least 90 seconds in; 60-second average within 12 s/km and 90th-to-10th percentile spread no more than 25 s/km; suppressed on meaningful grade. | Once per segment. |
| `pace_drift` | Recent pace slowed materially versus the runner's own earlier pace. | After 5 active minutes; recent 30-second average is 18 s/km slower in Coach Me or 25 s/km slower in Responsive than the preceding comparison window; not used in work/recovery or on meaningful grade. | At most every 10 minutes. |
| `rhythm_recovery` | A measured correction improved or stabilized pace relative to the cue target. | Evaluated 75 seconds after an eligible pace cue; current target error is at most 10 s/km, or improved by at least 8 s/km. | Once per helpful evaluated correction. |
| `recovery_too_hard` | Warmup, recovery, or cooldown pace is persistently faster than its personalized upper bound. | Same persistence and terrain gates as `pace_above_target`; phase must be warmup, recovery, or cooldown. | Once per segment. |
| `unexpected_stop` | Movement-based auto-pause paused an active workout. | Running speed remained below 1.0 m/s for 12 seconds after the first 10 active seconds. Manual pause does not create this moment. | Each actual auto-pause. |
| `resume_after_break` | Movement-based auto-pause resumed the workout. | Running speed remained at or above 1.5 m/s for 6 seconds while auto-paused. Manual resume does not create this moment. | Each actual auto-resume. |
| `climb_start` | Reliable altitude and location history indicate a sustained climb. | Running session; at least 90 active seconds; 45-second location window; grade at least 3.5%. | On transition into a climb, subject to coaching cooldown. |
| `crest_recovery` | A detected climb has eased enough to reset effort and rhythm. | Active climb state and rolling grade at or below 1.25%. | On transition out of a climb, subject to coaching cooldown. |
| `segment_transition` | A timed workout step ended and another began. | Cumulative duration boundary from structured workout steps. | Each segment boundary. |
| `finish_opportunity` | A planned finish is near enough for an optional controlled lift, but not an immediate finish command. | After 5 active minutes; 300-800 m or up to 12% remains for distance goals, or 2-5 minutes or up to 12% remains for time goals. | Once per session. |
| `challenge_start` | The runner explicitly enabled a 2- or 3-minute lift and enough workout remains. | After 6 active minutes; baseline pace exists; at least challenge duration plus 60 seconds remains when the goal is bounded. | Once per selected challenge. |
| `challenge_complete` | The selected challenge duration elapsed after its cue was spoken. | Challenge start was spoken and the selected duration elapsed. | Once per selected challenge. |

Pace values are accepted only from 60 through 3,600 seconds per kilometer. Rolling pace needs at least four valid samples. The director retains up to 240 active snapshots.

## Typed Workout Targets

`SessionCoachingTarget` makes workout meaning explicit instead of parsing localized labels. A target contains a phase, an optional pace band, and whether steady target-lock reinforcement is appropriate.

The athlete reference is the valid preferred pace when present, otherwise the median valid average pace in the recent guide profile. It is a personal reference, not a universal ability label.

| Phase | Resolved center | Faster tolerance | Slower tolerance | Target lock |
| --- | ---: | ---: | ---: | --- |
| Warmup | athlete reference + 30 s/km | 20 s/km | None | No |
| Easy/steady | athlete reference | 20 s/km | 35 s/km | Yes |
| Work/tempo/interval/race | No invented pace | None | None | No |
| Recovery | athlete reference + 45 s/km | 25 s/km | None | No |
| Walk | No pace target | None | None | No |
| Cooldown | athlete reference + 60 s/km | 30 s/km | None | No |
| Open/cross-train | No pace target | None | None | No |

An absolute pace prescription can use `absolute` instead of `athlete_reference`. Until a workout actually supplies one, work intervals remain effort-led and do not receive fabricated too-fast/too-slow cues.

Current plan steps, calibration workouts, the default easy run, standalone 5K/10K runs, and standalone speed-workout phases populate this contract. New workout sources must do the same.

## Terrain And Confidence Gates

Grade uses a 45-second window with at least six locations. Horizontal accuracy must be 25 m or better, vertical accuracy 10 m or better, and averaged endpoints must be at least 45 m apart. Values outside +/-40% are discarded.

An absolute grade of 2.5% or more suppresses pace correction, pace drift, instability, and target-lock praise. The coach should first acknowledge the hill and guide effort; flat-ground pace advice during a climb or descent is usually misleading.

Route guidance has priority over ordinary coaching. A live route cue also forces server generation to the fixed path for that request.

## Cooldowns, Outcomes, And Suppression

- Quiet has no automatic coaching cooldown and therefore emits no ordinary detector moments. Explicit challenges, progress, workout transitions, route/safety, and auto-pause status remain separate system behaviors.
- Responsive permits a new ordinary coaching moment after 180 seconds.
- Coach Me permits one after 90 seconds.
- Spoken pace corrections are evaluated after their delay. Only measured improvement or stabilization can produce `rhythm_recovery`.
- Responsive may locally suppress a moment type that repeatedly receives unhelpful outcome evidence.
- Exact pace, grade, location, heart rate, audio, and generated wording are excluded from product analytics. Analytics receives only bounded semantic moment, contract, provider result, and outcome values.

## Fixed Audio Compatibility

Catalog `2026-08-30.1` gives each correction a script that preserves its coaching meaning. Existing cues are reused only when they are already an exact fit, such as steady target confirmation, measured rhythm recovery, pause/resume, segment transitions, finishes, and challenges.

| Semantic moments | Reviewed fallback key |
| --- | --- |
| `progress`, `target_locked` | `progress.steady` |
| `early_overpace` | `coach.early_settle` |
| `pace_above_target` | `coach.ease_to_target` |
| `pace_below_target` | `coach.lift_to_target` |
| `pace_instability` | `coach.smooth_pace` |
| `pace_drift` | `coach.rebuild_rhythm` |
| `rhythm_recovery` | `coach.rhythm_recovered` |
| `recovery_too_hard` | `coach.recovery_easy` |
| `unexpected_stop` | `workout.pause` |
| `resume_after_break` | `workout.resume` |
| `climb_start` | `coach.climb_by_effort` |
| `crest_recovery` | `coach.crest_reset` |
| `segment_transition` | `workout.segment_start` |
| `finish_opportunity` | `coach.strong_finish` |
| `challenge_start`, `challenge_complete` | `challenge.start`, `challenge.complete` |

The transcript must exactly match the catalog entry when a fixed key is used. A catalog update and audio generation do not publish or deploy the cue: every new locale/voice rendition still requires human review, signed manifest publication, and an explicit catalog-version rollout; see `docs/live-coach-operations.md`.

## Candidate Taxonomy By Coaching Job

The implemented list is intentionally smaller than what a human running coach may notice. These names organize future work; they are not authorized for automatic speech until the stated signals and gates exist.

| Coaching job | Candidate moments | Required additions |
| --- | --- | --- |
| Pace execution | `negative_split_available`, `surge_detected`, `late_fade`, `repeat_too_fast`, `repeat_too_slow`, `repeat_consistency`, `final_repeat` | Explicit workout pace/power prescription, lap boundaries, personal response history |
| Recovery | `recovery_ready`, `recovery_incomplete`, `post_surge_settled`, `breaks_repeating` | Reliable HR or runner input; repeated-stop policy |
| Effort and heart rate | `effort_above_target`, `effort_below_target`, `cardiac_drift`, `heart_rate_recovered`, `heart_rate_sensor_unreliable` | Production Watch/strap ingestion, personalized zones/thresholds, source quality and dropout detection |
| Terrain | `descent_control`, `rolling_terrain`, `climb_effort_spike`, `technical_terrain_ahead` | Better elevation model, route surface/grade lookahead, HR or power |
| Form | `cadence_drop`, `cadence_change_available`, `ground_contact_asymmetry`, `vertical_oscillation_rise`, `posture_fatigue`, `overstriding_proxy` | Watch/pod running dynamics and pace-matched personal baselines; no universal cadence target |
| Breathing and perceived effort | `talk_test_above_target`, `rpe_above_target`, `rpe_below_target`, `breathing_settled` | Explicit runner voice/tap input or validated acoustic feature with consent |
| Fuel and hydration | `fuel_window`, `hydration_window`, `fuel_overdue`, `post_fuel_check` | Planned duration, runner strategy, weather, intake logging; reminders rather than medical claims |
| Environment | `heat_adjustment`, `cold_start`, `headwind_effort`, `poor_air_quality`, `low_light_awareness` | Fresh weather/AQI/light data, region-aware safety rules, no location in analytics |
| Race craft | `start_congestion`, `race_pace_locked`, `midrace_patience`, `passing_surge`, `final_kilometer`, `kick_available` | Race intent, course position/grade, validated goal pace, runner preference |
| Motivation | `rough_patch`, `comeback_confirmed`, `milestone`, `personal_best_possible`, `goal_complete` | Personal history, privacy-safe comparison, careful non-guaranteed wording |
| Safety | `runner_reported_pain`, `runner_reported_dizziness`, `runner_reported_chest_symptom`, `runner_requests_stop` | Explicit runner input and deterministic fixed responses; these must not be generative diagnoses |

## Heart Rate And "Lower Heart Rate"

Heart-rate moments are deferred, not rejected. The current snapshot has a heart-rate field, but production recording does not yet feed a live Watch or strap stream into it. A low reading can mean easy effort, recovery, medication, individual physiology, or sensor dropout. The app must not infer “push harder” from a low number alone.

The first HR release should require:

1. source identity and freshness;
2. dropout/artifact detection;
3. a runner-specific zone or tested threshold, not only an age-predicted maximum;
4. workout-phase context;
5. persistence and pace/grade cross-checks;
6. separate non-medical coaching and symptom-safety policies.

Safe first moments are likely `effort_above_target`, `effort_below_target`, `cardiac_drift`, `recovery_incomplete`, and `heart_rate_recovered`. “Abnormally low heart rate” is not a coaching cue; unexpected physiology belongs to health/safety guidance and requires explicit clinical review.

## Research Basis

The roadmap reflects normal coaching concerns rather than only what the phone currently measures:

- World Athletics training guidance distinguishes hills, intervals, tempo, progressive pacing, walking/jogging recovery, and individual adaptation: [road-running training guidance](https://worldathletics.org/competitions/world-athletics-road-running-championships/world-athletics-road-running-championships-7174065/for-participants/training), [speed training for endurance runners](https://worldathletics.org/personal-best/performance/speed-training-endurance-runners-benefits-limits), and [self-coaching guidance](https://worldathletics.org/personal-best/performance/mara-yamauchi-guide-be-your-own-coach).
- Garmin's documented running dynamics include cadence, stride length, ground-contact time/balance, vertical oscillation/ratio, power, and hill measures. Garmin also notes that height affects typical cadence and stride metrics: [running dynamics](https://www.garmin.com/en-ZA/garmin-technology/running-science/running-dynamics/).
- Cadence research supports personal, pace-matched baselines instead of a universal 180 spm rule: leg length and speed explain substantial cadence variation, while long-term injury evidence for changing step rate remains incomplete: [cadence predictors](https://pubmed.ncbi.nlm.nih.gov/36209689/) and [systematic review](https://pmc.ncbi.nlm.nih.gov/articles/PMC9441414/).
- Heart-rate zones can distinguish recovery, endurance, and hard work, but only relative to an athlete's zones: [Polar heart-rate zones](https://www.polar.com/us-en/guide/heart-rate-zones).
- Perceived effort and the talk test are useful alternatives/cross-checks when the runner can provide them: [CDC intensity guidance](https://www.cdc.gov/physicalactivity/basics/measuring/index.html).
- Symptoms are not coachable performance moments. Heart-related warning symptoms require stopping exercise and medical evaluation: [American Heart Association guidance](https://newsroom.heart.org/news/slow-steady-increase-in-exercise-intensity-is-best-for-heart-health-much-more-is-not-always-much-better).

## Delivery Phases

1. **Current:** typed workout targets; personalized pace bands; stability/lock/recovery evaluation; movement breaks; terrain detection and pace suppression; bounded semantic analytics.
2. **Wearable effort:** live Watch/strap HR with source quality, zones, drift, and recovery moments.
3. **Running dynamics:** cadence, power, ground contact, and form cues based on pace-matched personal baselines.
4. **Runner check-ins and safety:** talk test/RPE/fueling input plus deterministic symptom responses.
5. **Course and environment:** route lookahead, surface, weather, air quality, race strategy, and field validation.

Every phase needs replayable sensor fixtures, false-positive review across hills/stops/intervals, locale/audio review, analytics privacy review, and outdoor dogfooding before rollout.
