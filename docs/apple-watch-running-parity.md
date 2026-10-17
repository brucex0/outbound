# Apple Watch Running Parity

Open this for Apple Workout coexistence, standalone Watch recording, and the running replacement roadmap.

## Product decision

- P0: let runners keep Apple Workout while using Plainstride on iPhone.
- P1: complete phone-free route recording and the everyday running experience.
- P2 (deferred): execute prescribed interval workouts on the wrist; establish broader Apple Fitness/training-load parity through paired-device validation.
- P3 (deferred): sport-specific swimming, cycling, hiking, and multisport depth.
- watchOS permits one active workout session. Two live Watch recorders cannot run together. Apple reference: <https://developer.apple.com/documentation/healthkit/hkworkoutsession>.
- WorkoutKit plan export is a separate future integration, not part of this implementation.

## P0: Apple Workout mode

- The activity setup dock offers `Plainstride Watch` or `Apple Workout`; the selection persists.
- Plainstride mode retains mirrored start/pause/resume/finish and live heart rate.
- Apple Workout mode does not launch a Plainstride Watch session. Start/finish Apple Workout on Watch and Plainstride on iPhone independently; phone route, photos, and coaching continue normally. Watch heart rate is available after Health import, not live.
- Apple Workout mode suppresses phone Health write-back to avoid two Health workouts.
- After the mode is enabled, completed Apple-sourced workouts are imported when Plainstride launches or returns to foreground, subject to Health access and device sync.
- A unique same-sport phone recording with at least 80% overlap relative to the longer recording is linked instead of duplicated. Ambiguous or poorly overlapping recordings remain separate; no fuzzy merge deletes user data.
- Imported UUIDs make repeated scans idempotent. Other vendors continue through the existing confirmation sheet.

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

- `activity_configuration_changed`: `change_type=watch_recorder`, selection `apple_workout` or `plainstride`.
- `watch_workout_origin`: source `apple_workout` for coexistence starts.
- `watch_control_used`: source `apple_watch`; allowlisted controls `lap`, `auto_lap`, `goal_reached`, `zone_alert`, `pace_alert` over live mirroring. Offline control events are not uploaded individually.
- `health_import_completed`: selection `automatic_watch`, coarse count and success/failure.
- GPS, checkpoint, route save/retry, and Health import failures log operation and safe error category/code. Routes, Health values, UUIDs, and user content are excluded from diagnostics/analytics.

## Verification

- Do not run tests unless explicitly requested. Use build-only commands in `docs/build-test-device.md`.
- Paired-device acceptance still required: Apple Workout already active when phone recording starts; independent pause/finish; repeated imports; phone left at home; Watch airplane mode; GPS denial; pause/resume route gaps; process recovery; finish without connectivity; late Health route arrival; miles/km; laps/goals/haptics; and battery behavior on a long run.
- Build verification: standalone `Plainstride Watch` generic watchOS build and combined `Outbound` generic iOS build with signing disabled. Plist lint, localization catalog coverage, and `git diff --check` also passed. No test suite was run.
- Source review covered phone-first session-ID adoption, Watch-only import, repeated imports, route-before/after-workout delivery, phone-left-home distance reconciliation, pause/finish checkpoints, and suppression of discarded/deleted sessions. Manual activity edits remain authoritative during Health enrichment.
- Compilation and source review establish API/type correctness and review the intended paths; they do not establish GPS, Health delivery timing, ring credit, or real-device reliability.
