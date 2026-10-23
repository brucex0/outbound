# Live Coaching Moments

Open this when adding, tuning, suppressing, localizing, or analyzing a live coaching moment. This is the source of truth for the current definitions and the signal gates for future moments.

## Product Model

A coachable moment is not a sensor threshold by itself. The pipeline is:

```text
trusted signal + relevant workout context + baseline when needed + enough persistence
  -> semantic moment
  -> priority/cooldown decision
  -> dynamic wording or reviewed fixed cue
  -> optional outcome evaluation
```

The semantic moment says what happened. Audio wording may vary, but it must not change the workout, invent a target, diagnose a condition, or claim a sensor that was not supplied.

## Workout Execution Coaching and Automatic Cadence Beats

- iOS Today → workout Details retains the workout purpose and adds localized execution notes derived from typed phases: intended effort, pacing/breathing, controlled completion, and an optional shoulder/hand relaxation check. These are suggestions, never detected form or breathing faults. Existing targets and progression are unchanged.
- Planner prompt `2026-10-22.1` and reactive coaching allow a brief reason alongside one concrete action. Transition/instruction cues emphasize gradual starts, prescribed work effort, easy conversational effort, and recovery breathing; relevant later instructions may suggest a voluntary tension check. No universal cadence, breathing ratio, forward-lean prescription, or energy-saving claim is introduced.
- iOS `Guide/CadencePacer.swift` synthesizes a quiet drum beat per footfall. It uses the median of at least eight distinct cadence readings spanning 15 seconds in the latest 25 seconds; readings must be fresh within five seconds, 100–220 steps/minute, and vary by at most 12 steps/minute. These are eligibility bounds, not recommended cadence targets. Missing/unstable evidence means silence.
- Beats begin only after 90 active seconds and 30 seconds into an easy phase, with at least 35 seconds left and more than 200 m left for distance goals; unstructured easy/open running is also eligible. Structured unknown phases, work/recovery/warmup/cooldown/walk, completed workouts, and explicit races are excluded. Each segment lasts 20 seconds and fades over its final five seconds, with at least five active minutes between attempts.
- No new controls: beats follow existing companion-audio and Quiet preferences. Speech, queued coaching, and route guidance take priority. Pause, interruptions, headphone disconnection, stale cadence, and snapshot gaps stop beats; resumption requires new evidence. Beats mix with music; voice retains its existing ducking behavior. Beats never resume an interrupted segment or change workout targets.
- Cadence evidence remains on device. `live_guidance_pacer_playback` sends only `result = started/completed/interrupted/failed`, never cadence, timestamps, workout content, or identifiers. Existing planning-open and live-cue events cover preview/coaching usage.
- Scope: preview and beat playback are iOS-first; backend wording applies to clients using the shared live-coach service. No Android playback or Watch controls are added. Fixed reviewed audio packs are unchanged; richer wording requires dynamic server audio and a backend deployment. No data reset is required.
- Verification: backend TypeScript and iOS Simulator builds passed. Standalone checks of the actual waveform function confirmed 100/160/220-spm timing and fade; the extracted scheduling methods covered easy/structured running, cooldown spacing, missing/repeated/stale/unstable evidence, Quiet/occupied audio, races, short goals, and near-finish suppression. No test suite was run. Shared-resource ownership checks passed; the full drift check has the same 33 stale Android outputs on the unchanged baseline.
- Build checks do not establish headphone loudness, music mixing, interruption behavior, native-language presentation, or outdoor usefulness. Validate those on a physical device before release; generated phrases still pass the existing output validation and safety gates.

## Scheduled Execution Instructions and Debug Cadence

- Ordinary running sessions now receive server-authored `execution_coaching.*` instructions at 30 active seconds and every 120 seconds afterward, for up to two hours. Phase-specific effort guidance alternates with voluntary breathing, shoulder/hand relaxation, and gradual pacing checks. Text is authored in EN/ES/ZH and enters both generated and fallback phrase plans; fallback planning can therefore still use dynamic exact-text TTS and prewarming.
- These instructions use the existing `workout_instruction` contract and carry explicit IDs and elapsed triggers. iOS reads them from the active server plan; local catalog instructions remain unchanged. Quiet, fixed-only/safety-gated sessions, races, and curated execution catalogs receive no extra scheduled tips. Short phases and the final 30 seconds are excluded. Near-boundary instructions are skipped, and tips yield to queued corrections, speech, route guidance, and a 45-second speech gap. Missed windows are not replayed.
- An unavailable audio clip now releases the moment queue instead of retrying on every snapshot. Only successfully started playback enters duplicate suppression. Failures emit bounded diagnostics and existing availability events; no transcript, raw request, or personal data is logged.
- DEBUG route simulation supplies an explicit 164-spm cadence fixture on its synthetic session clock. It is not an inferred or recommended cadence and never populates physical-run sensor data. The pacer evaluates freshness against that clock so 1×/10×/60× simulation preserves the same evidence windows. Physical sessions still require fresh measured cadence.
- `live_guidance_execution_coaching` records only `result = scheduled/spoken/audio_unavailable`. No instruction ID, text, cadence, or timestamp enters analytics. Backend deployment and a new iOS debug build are required; already-created sessions retain their original plan.

## Current Phone-Sensor Definitions

These values are implemented in iOS `Guide/LiveGuidanceModels.swift` and `Guide/VirtualGuide.swift`, Android `android/feature/livecoach/.../policy/LiveCoachMomentPolicy.kt` and `LiveCoachViewModel.kt`, and the backend live-coach contract.

| Moment | Current definition | Signal and context | Frequency |
| --- | --- | --- | --- |
| `progress` | A factual progress or goal update is due. | Default every 3 active minutes or each 1 km/1 mi for running; goal milestones and reliable-distance gates can alter timing. | Existing progress cadence and speech-gap rules. |
| `early_overpace` | The first sustained running pace is faster than the active workout target. | 30-second average, 75-240 active seconds, faster by the target's tolerance; suppressed on meaningful grade. | Once per session. |
| `pace_above_target` | Pace is persistently faster than a pace-enabled non-recovery workout segment or a validated typed race target. | Workout segment: at least 45 seconds into the segment; 30-second average exceeds the faster edge of its personalized pace band. Race: at least 30 active seconds; 30-second average is at least 20 s/km faster than target. Both are suppressed on meaningful grade. | Once per segment; race target once per race. |
| `pace_below_target` | Pace is persistently slower than a segment that explicitly allows a lower-bound cue or a validated typed race target. | Workout segment: at least 45 seconds into the segment; 30-second average exceeds the slower edge. Race: at least 30 active seconds; 30-second average is at least 30 s/km slower than target. Both are suppressed on meaningful grade. Warmup, recovery, and cooldown intentionally have no slower edge. | Once per segment; race target once per race. |
| `pace_instability` | Two established pace periods differ enough that a sustainable rhythm is more useful than a faster/slower command. | Outside work/recovery steps, after 180 active seconds in both the session and current segment; compare the median pace in the 90-60 second and latest 30-second windows. Each window needs at least 8 distinct active seconds of valid pace spanning at least 20 seconds. Each window must also have a 90th-to-10th percentile spread no greater than 30 s/km. The medians must differ by at least 60 s/km or 15% of the active target, whichever is greater, while recent pace is at least 35 s/km outside that target for 15 additional active seconds; suppressed on meaningful grade. No active target means no instability correction. | Ordinary contract cooldown plus a 3-minute minimum; rearmed only after the compared difference falls below half the threshold. |
| `target_locked` | The runner has held a target accurately and smoothly long enough to reinforce it. | Segment opts in; at least 90 seconds in; 60-second average within 12 s/km and 90th-to-10th percentile spread no more than 25 s/km; suppressed on meaningful grade. | Once per segment. |
| `pace_drift` | Recent pace slowed materially and is outside an active workout target. | After 5 active minutes; recent 30-second average is 18 s/km slower in Coach Me or 25 s/km slower in Responsive than the preceding comparison window; both windows must be stable (spread at most 30 s/km), and the recent pace must also exceed the active target by the same threshold; not used in work/recovery or on meaningful grade. | At most every 10 minutes. |
| `rhythm_recovery` | A measured correction improved or stabilized pace relative to the cue target. | Evaluated 75 seconds after an eligible pace cue; current target error is at most 10 s/km, or improved by at least 8 s/km. | Once per helpful evaluated correction. |
| `recovery_too_hard` | Warmup, recovery, or cooldown pace is persistently faster than its personalized upper bound. | Same persistence and terrain gates as `pace_above_target`; phase must be warmup, recovery, or cooldown. | Once per segment. |
| `unexpected_stop` | Movement-based auto-pause paused an active workout. | Running speed remained below 1.0 m/s for 12 seconds after the first 10 active seconds. Manual pause does not create this moment. | Each actual auto-pause. |
| `resume_after_break` | Movement-based auto-pause resumed the workout. | Running speed remained at or above 1.5 m/s for 6 seconds while auto-paused. Manual resume does not create this moment. | Each actual auto-resume. |
| `climb_start` | Reliable altitude and location history indicate a sustained climb. | Running session; at least 5 active minutes so startup altitude can settle; reliable 45-second location window; grade at least 3.5% persists for another 30 m. | On transition into a climb, subject to coaching cooldown. |
| `crest_recovery` | A detected climb has eased enough to reset effort and rhythm. | Active climb state and rolling grade at or below 1.25%. | On transition out of a climb, subject to coaching cooldown. |
| `segment_transition` | A timed workout step ended and another began. | Cumulative duration boundary from structured workout steps. | Each segment boundary. |
| `finish_opportunity` | A planned finish is near enough for an optional controlled lift, but not an immediate finish command. | After 5 active minutes; 300-800 m or up to 12% remains for distance goals, or 2-5 minutes or up to 12% remains for time goals. | Once per session. |
| `race_start_restraint` | Establishes patience at the beginning of an explicitly planned race. | Typed race intent; after 75 active seconds and before 15% progress. Does not claim a pacing error. | Once per race, including Quiet. |
| `race_pace_locked` | Confirms a validated race target has been held. | Typed target pace; 15-70% progress; three-minute average within 12 s/km; suppressed on meaningful grade. | Once per race. |
| `race_halfway_assessment` | Marks halfway and favors patient execution rather than an automatic surge. | Typed race distance and at least 49% measured progress. | Once per race, including Quiet. |
| `race_late_fade` | Helps restore sustainable rhythm when pace is persistently outside the race target late. | At least 70% progress; two-minute average at least 20 s/km slower than target; suppressed on meaningful grade. | Once per race. |
| `race_late_strength` | Offers a conditional gradual build when target execution remains controlled late. | At least 76% progress; three-minute average no more than 10 s/km slower than target; no prior fade; not effort-only; suppressed on meaningful grade. | Once per race. |
| `race_final_kilometer` | Starts final-kilometer execution without issuing a sprint command. | Typed race distance with no more than 1,000 measured meters remaining. | Once per race, including Quiet. |
| `challenge_start` | The runner explicitly enabled a 2- or 3-minute lift and enough workout remains. | After 6 active minutes; baseline pace exists; at least challenge duration plus 60 seconds remains when the goal is bounded. | Once per selected challenge. |
| `challenge_complete` | The selected challenge duration elapsed after its cue was spoken. | Challenge start was spoken and the selected duration elapsed. | Once per selected challenge. |
| `workout_instruction` | A selected standalone workout reached a catalog-authored execution boundary. | Exact instruction ID plus a distance or elapsed-time trigger carried in the cached workout; the server-issued phrase plan carries the matching ID and trigger. | Once per instruction ID; stale crossings are skipped. |

Coaching additionally requires the latest GPS fix to be no older than 5 seconds, at least eight distinct fixes spanning 20 seconds within the latest 30 seconds, horizontal accuracy no worse than 20 m, and no fix gap longer than 5 seconds. Coaching snapshots carry the latest accepted evidence timestamp locally; repeated UI ticks of the same fix cannot count as new samples. Display pace remains available independently. All pace-based rolling windows require eight distinct evidence timestamps spanning at least 20 active seconds and at least two thirds of the requested window. Missing evidence, wall-clock snapshot gaps over 8 seconds, and pause/resume clear pace history and pending outcome measurements while preserving cooldowns and the repeat latch. Pauses also discard queued pace corrections; iOS discards unreliable or over-10-second-old queued pace moments.

Pace values are accepted only from 60 through 3,600 seconds per kilometer. Rolling coaching pace needs at least eight distinct valid evidence samples with the coverage described above. The guide retains 240 active seconds of history so accelerated run simulations preserve the same detector windows as live sessions. Android delivers each simulated second through a buffered coaching stream because its UI state stream conflates rapid updates; its live-coach request omits absent optional fields so the server accepts the session and supplies the audio pack.

iOS accelerated simulations evaluate fix freshness against their synthetic session clock. Physical GPS continues to use wall-clock freshness. Both paths retain the same accuracy, sample-count, coverage, and gap gates; repeated snapshots of one fix do not become new evidence.

The instability detector waits for established pace because the first GPS pace estimate can include a pre-start location fix and is refreshed from overlapping 30-second windows. Counting eight one-second snapshots from that settling estimate caused false early pace-change cues.

Android evaluates major pace instability within its ordinary coaching cooldown and carries an optional typed race intent from the recording launch into live-coach context. Android currently has no race-planner entry point, so that race-specific detector is active only when a launch supplies a validated race target; ordinary typed workout targets continue to use their segment-specific pace bands.

The `routeGuidanceActive` live-state field means a spoken route instruction is temporarily occupying the guide audio path, as on iOS. Selecting or simulating a followed route alone does not set it. Android does not yet speak route instructions, so its live-coach requests leave this field false and keep pace and progress cues eligible.

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

Grade uses a 45-second window spanning at least 30 seconds with at least eight reliable snapshots. Horizontal accuracy must be 20 m or better and vertical accuracy 8 m or better. The runner must advance at least 75 m, the averaged endpoints must be at least 40 m apart, and the altitude change must exceed both 6 m and the reported endpoint vertical uncertainty. Grade uses recorded path distance rather than straight-line endpoint distance, so turns do not exaggerate slope. Values outside +/-40% are discarded. A climb cue additionally requires the qualifying grade to persist for another 30 m; loss of a reliable qualifying signal resets that candidate.

An absolute grade of 2.5% or more suppresses pace correction, pace drift, instability, and target-lock praise. The coach should first acknowledge the hill and guide effort; flat-ground pace advice during a climb or descent is usually misleading.

Route guidance has priority over ordinary coaching. A live route cue also forces server generation to the fixed path for that request.

## Cooldowns, Outcomes, And Suppression

- Quiet has no automatic coaching cooldown and therefore emits no ordinary detector moments. Explicit challenges, progress, selected-workout instructions, workout transitions, route/safety, and auto-pause status remain separate system behaviors.
- Responsive permits a new ordinary coaching moment after 180 seconds. Pace instability now respects this cooldown rather than bypassing it.
- Validated race-target pace deviations are evaluated before the ordinary coaching cooldown, so a 30-second average that crosses either race threshold can cue promptly; each direction can cue once per race.
- Coach Me permits one after 90 seconds.
- Spoken pace corrections are evaluated after their delay. Only measured improvement or stabilization can produce `rhythm_recovery`.
- Responsive may locally suppress a moment type that repeatedly receives unhelpful outcome evidence.
- Exact pace, grade, location, heart rate, audio, and generated wording are excluded from product analytics. Analytics receives only bounded semantic moment, contract, provider result, and outcome values.

## Fixed Audio Compatibility

Catalog `2026-08-30.1` introduced a script for each correction that preserves its coaching meaning, and successor catalogs retain that mapping. Existing cues are reused only when they are already an exact fit, such as steady target confirmation, measured rhythm recovery, pause/resume, segment transitions, finishes, and challenges.

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
| `workout_instruction` | Instruction-specific planned phrase; `workout.segment_start` is the generic localized fallback |
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
| Race craft | `start_congestion`, `midrace_patience`, `passing_surge`, `kick_available` | Better course-position context, runner input, and validated safe finish-location evidence |
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

## Local Reference Fallback

- iOS loads the cached guide profile before fetching the server and accepts equal-version server responses into memory. Fetch failures log only a normalized error category.
- When the guide profile has no valid pace reference, coaching uses the median valid pace of up to ten saved runs from the last 30 days, each at least five minutes and 500 m. Missing average pace may be derived from recorded moving time and distance. Future-dated, stale, non-running, short, and invalid-pace activities are excluded.
- This fallback is held in memory for coaching only; it does not overwrite the server profile or its cached version. No eligible history means no invented reference or target. Workout offsets, terrain, confidence, persistence, and cooldown gates remain unchanged.
- Preparation keys include the effective reference pace so changed local evidence invalidates a pending preparation.

### Android saved-run pace reference

- Catalog `athlete_reference` targets resolve at launch from the median pace of up to 10 most recent eligible local runs in 30 days (at least 5 minutes and 500 m), plus the catalog offset. Deleted, future, malformed, and implausible records are excluded.
- Absolute workout/race targets remain authoritative; effort-only workouts and missing history do not invent a pace. The reference is account-scoped and in memory; no storage reset is needed.
- `live_guidance_reference_resolved` and `PlainstrideLiveCoach` report only `local_history` or `unavailable`, without raw pace or history.

## Independent Sudden Speed Changes (iOS and Android)

- Runs without a guide profile or target pace in Responsive and Coach Me; Quiet stays quiet. Uses distinct trusted GPS speed samples rather than the smoothed display pace.
- Compares a 5-second speed median with a preceding stable 20-second baseline (at least 8 fixes spanning 14 seconds; each speed within 20% of its median). Requires a running baseline of at least 1.5 m/s, a change of both 40% and 3 km/h, then 5 seconds of persistence. A clean 1 Hz step change triggers after about 8 seconds.
- iOS pairs incoming GPS speed with its matching evidence timestamp before publishing the live snapshot. Multiple distinct fixes in one active second retain the latest fix without clearing the detector baseline or inflating sample coverage.
- Rejects missing/nonfinite/out-of-range speeds, repeated fixes, reversed timestamps, and gaps over 5 seconds. Recording reliability gates still apply. Pause/resume and segment changes clear evidence; the first 30 seconds of a typed segment are excluded. Slowdowns in warmup, recovery, cooldown, or walking are excluded.
- Uses a 60-second detector cooldown and deduplicates against recent coaching. Changes during cooldown cannot produce a delayed stale alert. Target-dependent guidance remains separate.
- Reuses the semantic `pace_instability` queue and existing reviewed `coach.settle` / `coach.restore_rhythm` clips, prewarmed for the selected voice and language. Local playback never requests AI or runtime synthesis. Missing matching audio is diagnosed and remains silent; route and workout audio retain priority.
- `live_guidance_speed_change` records only `source_type=increase|decrease` and `result=detected|spoken|audio_unavailable`; existing cue analytics remain active. No raw speed, location, or history is recorded.
- Verification: permanent iOS detector and recorder/guide tests cover both sustained directions, spikes/rapid alternation, thresholds, repeated/same-second evidence, invalid samples, gaps/pause/segment resets, easy-phase suppression, startup, and stale cooldown candidates. Pipeline tests cover coaching contracts, non-running sessions, busy/expired/unreliable queues, unavailable clips, failed playback, and the actual Debug simulation through the recorder to the reviewed-audio request. Restoring the old snapshot pairing and same-second reset bugs makes their respective regression tests fail. Run the focused command in `docs/build-test-device.md`; physical device audibility remains unverified by these tests.

- Android applies the same detector thresholds and reset rules using reliable raw location speed, including buffered simulation samples. It preloads the same reviewed clips and uses cache-only playback for this path, preserving workout-boundary priority. An alert delayed over 10 active seconds or losing reliable evidence is dropped with `result=stale`. Android debug build and equivalent standalone Kotlin replays passed; device audibility remains unverified.
