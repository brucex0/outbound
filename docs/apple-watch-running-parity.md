# Apple Watch Running Parity

Open this for Apple Workout coexistence, standalone Watch recording, and the running replacement roadmap.

## Product decision

- P0: let runners keep Apple Workout while using Plainstride on iPhone.
- P1: complete phone-free route recording and the everyday running experience.
- P2 (deferred): execute prescribed interval workouts on the wrist; establish broader Apple Fitness/training-load parity through paired-device validation.
- P3 (deferred): sport-specific swimming, cycling, hiking, and multisport depth.
- watchOS permits one active workout session. Two live Watch recorders cannot run together. Apple reference: <https://developer.apple.com/documentation/healthkit/hkworkoutsession>.
- WorkoutKit plan export is a separate future integration, not part of this implementation.

## Watch app toggle and Health saving

- The activity setup dock has a text-only `Watch app` toggle. Selected means on, unselected means off; accessibility announces On/Off and explains that this starts Plainstride on Apple Watch. It defaults on and persists in `watch.startWatchApp`.
- This replaces the former recorder selector. The old `watch.useAppleWorkout` preference is no longer used; the new toggle starts on until the runner changes it.
- On retains automatic Watch launch, mirrored start/pause/resume/finish, and live heart rate. Off records on the phone without launching our Watch app or assuming Apple Workout is running. Manually starting Plainstride on Watch still supports Watch-first recording.
- Phone route, photos, and coaching continue in either state. Apple Workout, if used, must be started and finished independently; there is no live Apple Workout detection or control.
- Saving the phone activity attempts normal Health write-back unless a successful Plainstride Watch save is confirmed for the same session UUID with a valid saved Health workout UUID. Watch ownership, the toggle state, and time/sport overlap alone never suppress the save. The confirmation can come from the matching Watch save acknowledgement or an exact session-linked Health import.
- If the Watch is disconnected, its save fails, or confirmation has not arrived when the phone saves, the phone attempts Health write-back. A later Watch save or an independently recorded Apple workout can therefore produce a second Health workout; preserving the recording takes priority over speculative deduplication. Health write permission is still required.
- Completed Plainstride Watch workouts are automatically imported/reconciled on launch and foreground using their exact Plainstride session UUID. Apple and other external workouts remain available through the existing Health import review; they are no longer automatically imported based on a recorder preference or linked by an 80% time-overlap guess.
- Imported Health UUIDs make repeated scans idempotent. No fuzzy merge deletes user data.

## P1: Standalone Watch recording

- Watch owns workout metrics and Health persistence. Outdoor run/walk/cycle/hike sessions also collect Watch GPS.
- A local route journal appends valid GPS samples at most every ten seconds and flushes on pause/finish (up to ten seconds of buffered points can be lost to abrupt termination); pause stops collection, and recovery reopens the same session journal.
- Finishing attaches the route to the Health workout. Failed route writes retain the journal for retry on a later Watch launch. Retry checks for an existing attached route before writing again.
- Health sync carries completed Watch-only workouts to iPhone even when live mirroring was unavailable. Plainstride session UUIDs link mirrored records or create one imported activity.
- Routes can arrive after workout metadata; foreground reconciliation revisits recent linked records for late route data. A clearly incomplete phone route can be replaced by the Watch route when its recorded distance is below 80% of the Watch distance.
- GPS/location permission is optional for workout recording; denied GPS means metrics can save without a route.
- Discarding a phone review still does not delete the independently saved Health workout. Discarded/deleted Plainstride session UUIDs are remembered locally so delayed Watch import does not resurrect them.

## P1: Everyday running UI

- Swipe between summary/controls, pace, and heart-rate pages; pace/heart pages can be hidden in Running settings.
- Summary shows elapsed time, distance, active energy, goal completion, pause/resume, manual lap, and confirmed finish.
- Pace includes current rolling pace, average pace, current lap pace, and recent lap paces. Current pace requires at least five seconds and two meters in a rolling 15-second window; unavailable data displays a dash.
- Miles/km setting controls distance, pace, and automatic split length (one mile or one kilometer).
- Automatic splits and manual laps vibrate and add lap events to the Health workout.
- Watch settings support open, distance, or time goals; goals notify without ending a workout.
- Optional zone-change alerts have a 30-second cooldown; optional target-pace alerts use a 30 sec/km tolerance and a 60-second cooldown. They are simple haptic notifications, not prescribed workout execution.
- All new display strings include English, Spanish, and Simplified Chinese translations.

## Analytics and diagnostics

- `activity_configuration_changed`: `change_type=watch_app`, selection `enabled` or `disabled`.
- `watch_workout_origin`: source `iphone` for phone starts, including Watch app off; `apple_watch` for Watch-first starts.
- `health_workout_write_back`: source `iphone` with result `success`/`failure`, or source `apple_watch` with result `skipped_confirmed_save`; failures include only a normalized error category.
- `watch_control_used`: source `apple_watch`; allowlisted controls `lap`, `auto_lap`, `goal_reached`, `zone_alert`, `pace_alert` over live mirroring. Offline control events are not uploaded individually.
- `health_import_completed`: selection `automatic_watch`, coarse count and success/failure.
- GPS, checkpoint, route save/retry, and Health import failures log operation and safe error category/code. Routes, Health values, UUIDs, and user content are excluded from diagnostics/analytics.

## Verification

- Watch app toggle / confirmed-save update (2026-10-18): generic iOS Simulator build passed with signing disabled; Swift syntax, English/Spanish/Simplified Chinese catalog coverage, and diff whitespace checks passed. Source review covered on/off launch routing, confirmed/missing/failed/late acknowledgements, session-ID mismatch, and clearing coordinator state after save. No tests were run; visual toggle checks and paired-device Health delivery remain unverified.

- Automated simulator flow coverage and the repeatable runner are documented in `docs/build-test-device.md` under **Watch And Phone-Only Regression Flows**.

- Do not run tests unless explicitly requested. Use build-only commands in `docs/build-test-device.md`.
- Paired-device acceptance still required: Watch app on/off persistence and selected styling; phone save with no Apple Workout running; Apple Workout already active when phone recording starts; independent pause/finish; confirmed/missing/late/failed Watch saves; repeated imports; phone left at home; Watch airplane mode; GPS denial; pause/resume route gaps; process recovery; finish without connectivity; late Health route arrival; miles/km; laps/goals/haptics; and battery behavior on a long run.
- Build verification: standalone `Plainstride Watch` generic watchOS build and combined `Outbound` generic iOS build with signing disabled. Plist lint, localization catalog coverage, and `git diff --check` also passed. The historical recorder-selector Watch/phone flow suite passed six cases on an iOS 26.5 iPhone simulator before the Watch app toggle change; the updated fixture has not been rerun.
- Source review covered phone-first session-ID adoption, Watch-only import, repeated imports, route-before/after-workout delivery, phone-left-home distance reconciliation, pause/finish checkpoints, and suppression of discarded/deleted sessions. Manual activity edits remain authoritative during Health enrichment.
- Compilation and source review establish API/type correctness and review the intended paths; they do not establish GPS, Health delivery timing, ring credit, or real-device reliability.
