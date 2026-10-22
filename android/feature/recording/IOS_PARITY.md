# Recording iOS Parity

## Authority And Counterparts

- iOS root and state handoff: `ios/Outbound/Outbound/Activity/RecordView.swift`
- iOS map and camera workout panels: `ios/Outbound/Outbound/Activity/LiveMapView.swift` and `ios/Outbound/Outbound/Camera/CameraHUDView.swift`
- iOS recorder, location, journal, and Live Activity: `ActivityRecorder.swift`, `LocationManager.swift`, `ActiveSessionJournal.swift`, and `SessionLiveActivityManager.swift`
- Android route and UI: `RecordingScreen.kt` and `RecordingViewModel.kt`
- Android process owner, location, and journal: `RecordingService.kt`, `RecordingCoordinator.kt`, `FusedRecordingLocationSource.kt`, and the Room active-session journal

## States And Transitions

- Today launches the prepared activity directly into location readiness and then a cancelable, spoken 3–2–1–Go countdown when Voice Guide is enabled; the recording setup screen is not shown during this direct-start flow. Today's activity, goal, and Voice Guide selection take precedence over a saved setup during direct launches. The countdown uses a high-contrast circular progress treatment and a 420 ms Go beat to match iOS.
- Outdoor activity start follows iOS preflight: explain location use before the system prompt, direct previously denied users to app settings, refresh authorization when returning from settings, and hold the start until a location fix is no older than 15 seconds and no less accurate than 80 meters. Indoor sessions bypass both gates. A lost permission or GPS fix during countdown blocks recording and returns to the matching permission or acquisition state.
- Outdoor activity setup also shows the iOS “Enable location” chip while access is unavailable. It opens the same explanation and first-request versus app-settings path as Today and weather; indoor setup hides the chip.
- Active recording is non-dismissible. Pause reveals separate Resume and Finish controls; Finish requires confirmation.
- The map and camera share compact and expanded dashboard state. Tap or vertical drag changes state without dismissing the activity.
- The compact dashboard mirrors iOS's glanceable time / primary action / optional Finish / distance row; the expanded dashboard owns the title and status, goal hero, progress, metric cards, current workout step, route name, and labeled controls.
- Running's expanded dashboard shows localized `Steps / min` from the phone step detector. Optional Activity Recognition access is requested once before a real Run start; denial or unsupported hardware leaves the metric unavailable and does not block recording. No synthetic cadence is shown for debug route simulation.
- Steps-per-minute statistics and a segmented active-time chart appear in finish review and saved detail. Pauses stop step collection, stale values clear after ten seconds, recovery retains measured statistics, and missing intervals never become zero cadence. The saved private payload is compatible with iOS's cadence summary and samples.
- The primary live metric follows the selected distance, time, calorie, structured-workout, or freestyle goal.
- Sessions launched with `Stop at goal` enabled finish automatically at the distance, elapsed-time, or estimated-calorie target and move directly to review. Recovery retains the choice; paused sessions do not auto-finish.
- Live distance, pace, elevation, target progress, and calorie estimates honor the runner's persisted measurement and weight preferences, matching the iOS formatter and estimator contracts.
- Auto Pause is configurable from setup for run, bike, walk, and hike; each sport keeps its own choice. Run and bike default on, while walk and hike default off. Automatic pauses freeze the activity clock but keep a brief location probe active for confirmed movement and resume; average pace follows the same active-time clock as activity duration.
- Capturing a photo keeps the live camera preview running and moves the result into a private thumbnail instead of replacing the workout surface.
- The live map opens on the runner, keeps native pan/zoom controls, renders the selected route and recorded trail separately, and does not continuously zoom out as new samples arrive. The DEBUG simulator frames the planned route first, then follows its synthetic runner marker as time advances.
- Recovery returns to the live surface paused; completion stays in the same route for reflection, local save, or confirmed discard. Confirmed discard waits for the recording service to reach idle before navigating away, preventing recovery from reopening the discarded activity.
- Finish remains disabled while required photo persistence is pending.
- DEBUG setup includes the iOS Redmond Harvest run simulator. Android Debug route discovery always includes the Redmond route marked `Test`; selecting it to start a run automatically enables the simulator. It samples the same route through the recording location filter, route map, and live metrics without requiring the device to move, though Android still requires location permission to start its location-typed foreground service. The live overlay provides adjustable speed, an iOS-style 1×/10×/60× rate dropdown, visible start/pause control, and +1m/+5m deterministic advances. Synthetic sessions remain subject to the normal finish, review, save, and discard flow.
- Offline setup and active recording show an activity-specific status that confirms the activity is saved on device and will sync later; the signed-in shell banner is hidden while this route is visible.
- Post-run review leads with the recorded route (or a non-route activity hero), overlays the close and Save controls like iOS, and follows with contextual motivation, core stats, optional perceived effort, and photo review.
- The finish photo manager supports multiple imported or camera photos, full-screen paging, long-press multi-select, selected-photo removal, and order changes. Imports preserve EXIF date and GPS when available, are orientation-corrected and bounded to a 2048-pixel longest edge, and map to interpolated route distance. GPS pins use embedded coordinates only when they fall within 500 meters of the route; otherwise, the capture time maps to the nearest recorded route sample. Android uses the system camera and photo picker in place of iOS's in-app camera and PhotosPicker.
- The finish hero pages between route and photos. Photo captions follow iOS start / finish / route-distance rules, and every ordered photo with its capture time, route distance, plausible coordinate, and capture context is persisted with the activity.
- Perceived effort matches iOS Easy / About right / Too hard choices, with continuation capacity shown only for Easy. Feedback is submitted through the existing workout feedback endpoint when the runner selected an answer. Finish stats use the shared calorie estimator and account measurement units.
- Save is disabled below the shared iOS threshold of five minutes or 500 meters. Closing an eligible unsaved review requires destructive confirmation; an ineligible review closes directly, matching iOS.
- A successful local save shows the shared activity postcard before the activity-surface exit. For Run, Bike, Hike, and Swim, the postcard and message sit above the same two optional stretch choices as iOS: a full-body cooldown and a focused hips-and-hamstrings routine. Other activity types show the postcard on its own. The postcard traces the saved route (or fixed doodle path without a route), uses the shared vector runner and sundae burst, fades the sundae after a short pause, stays open until the runner chooses Done, and respects Android animator-duration scale. Analytics records the existing `feature_exposed/activity_post_save_celebration` exposure and stretch funnel with stable routine IDs only.

## Ad-hoc Race Mode

- Run alone exposes the text-only Race pill. Opening or canceling its planner does not replace the current setup; Apply installs the distance goal, localized Race day title, execution guidance, and typed race context. Route, shoes, companion, indoor, and voice choices remain independent. Switching to another sport leaves Race mode.
- The planner matches `RacePlannerView.swift`: 5K/10K/half/marathon, half-marathon initial selection, recent-history recommendation, editable hour/minute time, negative split/even/effort strategies, and localized guidance in the selected measurement units. Reopening reseeds instead of editing the applied plan. Exact filters, rounding, and the iOS no-history two-hour default are documented in `docs/activity-launch-live-ux.md`.
- Race remains a saved distance goal, with no Pause at goal. Guidance carries race distance, time, strategy, source, and optional pace through the existing serializable launch/recovery context and live-coach request. Targeted pacing uses iOS work phase, 15-second faster/20-second slower tolerance, and target-lock recognition.
- Race configuration analytics use the shared event names, recommendation-source/strategy enums and coarse distance bucket; start/save report `goal_type=race`. No exact targets or training history enter analytics.
- Verification: source-level comparison covers no/insufficient history, distance filters, comparable-distance selection, near-distance clamping, buffered projections, minute rounding, manual edits, by-feel pace removal, distance launch goals, and live-coach/recovery wiring. Device visual, rotation, real recording, and process-recovery verification remain pending; a build does not establish those behaviors.

## Elevation Correction

- Live/offline elevation now uses the current iOS directional accumulator, retaining accuracy/spike filters and a conservative 10 m climb threshold. Descents do not create ascent; pause boundaries commit active climbs without counting the gap.
- Save commits the activity, original samples, and outbox locally before any terrain request. Sync attempts correction within a 15-second batch budget before upload; unavailable/unsupported providers leave the saved result intact, with retry available when detail opens. Terrain requests use equal-distance samples, preserve segment endpoints, and remain within the shared 450-point budget.
- Room schema 5 adds nullable correction metadata and a separate local-only original-route blob table. Android is unreleased: a schema-versioned database name opens clean local Room data without copying old databases. Backend data is unchanged and can sync back down. No migration is run. Original samples are gzip-compressed JSON, never added to relations/uploads, retained only once, and removed on local/remote activity deletion or account-data clearing. Previously overwritten source altitude cannot be recovered.
- The correction implementation is in `core/data/TerrainElevationCorrector.kt`, sampling/directional logic in `core/model/activity`, and lifecycle/sync guards in `core/data/ActivityRepository.kt`. Shared algorithm details and deployment ordering remain in `docs/activity-detail.md`.

## Resources, Analytics, And Accessibility

- Visible strings use generated shared localization resources in `src/main/res`.
- Setup is tracked only when its screen is shown. Start, pause, resume, finish, save eligibility, discard, surface, media, dashboard-state, and Auto Pause configuration events use the canonical sanitized iOS event names and Android platform property.
- Debug builds log direct-launch Voice Guide precedence, TTS engine initialization and locale selection, countdown cue enqueue results, and TTS playback callbacks under `RecordingStart` and `RecordingVoice`; logs never include spoken text.
- Terrain correction emits the shared `activity_elevation_correction_completed` event with bounded source/result/latency/error only; coordinates, altitude, gain, timestamps, and activity IDs are excluded. Cancellation is not logged as an error; other failures log the operation, exception type, category, and HTTP status without response bodies.
- The debug simulator uses `activity_configuration_changed`, `activity_simulation_started`, and `activity_simulation_control_used` with the iOS allowlisted property names and coarse speed/distance values.
- Controls expose semantic labels, retain 48dp-or-larger primary targets, and do not rely on color alone. Reduced motion shows the completed route and fully formed sundae without tracing or flying sprinkles, then fades the sundae after a short pause.

## Reference Scenarios

- Outdoor starts with location not yet requested, denied once, permanently denied, revoked in app settings, approximate, and precise; fresh, stale, inaccurate, and unavailable GPS fixes; permission loss during countdown; and indoor start without location.
- Planned distance workout, manual free run, timed walk, calorie goal, structured workout, and followed route.
- DEBUG Redmond simulated run with no GPS fix, 4–24 km/h speed bounds, all three time rates, manual time jumps, normal pause/resume, route completion, and discard.
- Active and paused map/camera surfaces, compact and expanded dashboard, pending photo write, finish confirmation, recovery, and post-run review.
- Motion permission allowed/denied, unsupported step detector, steady and changing step timing, sensor gaps, manual/automatic pause, process recovery, and saved/synced cadence charts.
- English, Spanish, and Simplified Chinese; light/dark themes; compact phone and increased font scale.
- Offline before start, during map and camera recording, and during a connectivity recovery while an activity remains active.

## Current Status

- Core start/spoken 3–2–1–Go countdown, foreground recording, pause/resume/finish, camera/map switching, in-session voice commands, route-aware live mapping, recovery, review, local save, and the iOS compact/expanded dashboard hierarchy are implemented. Countdown speech checks the selected app locale and falls back to a supported language before reporting speech readiness.
- DEBUG interactive Redmond run simulation is implemented with the iOS route fixture and synthetic locations routed through the normal recorder snapshot pipeline.
- Visible live heart rate/walking total steps, coach text, music controls, and group-run strips remain dependent on those data streams being exposed to the recording UI; their audio, wearable, music, and safety owners are implemented separately.
- Manual visual comparison and real-device longevity/background validation remain release-gate work.

## Approved Exceptions

- Android uses an ongoing foreground-service notification instead of ActivityKit. It owns equivalent active/paused status and Pause/Resume actions at the Android platform boundary.

## Moving-time accounting

- Phone Run/Walk/Hike/Bike keep `elapsedSeconds` as the internal active workout clock and checkpoint a separate stop ledger; the public saved `durationSecs` is moving time. Wall-clock elapsed duration comes from the existing start/end timestamps.
- Shared thresholds, confidence rules, UI semantics, source limits, and outdoor acceptance checks: `docs/activity-detail.md`, Moving And Elapsed Time.
- The journal payload adds current stop-accounting state; Room tables and database version are unchanged. No local data reset is required. Confirmed stops survive process recovery; an interrupted candidate is cleared.

- Stop accounting consumes raw fused-location observation timestamps before the route filter drops stationary fixes. UI ticks only publish the accumulated result. A zero distance minimum keeps stationary observations available; source confidence and the 30-second gap bound match iOS.

## Post-save Quick Sharing

- Both celebration-only and stretch-offer layouts show Share beside Done immediately below the celebration message. Share opens the existing Android card preview for the locally saved activity, with Save Image and the native share chooser. Closing sharing retains the post-save surface and stretch selection.
- Sharing does not wait for backend sync. Save failure never supplies a shareable activity. Preparation/save/chooser failures show temporary localized feedback and safe technical diagnostics. Existing share events use `source_type=post_save`, with no IDs, coordinates, exact metrics, or photo content.
- Verification: recording/activity Kotlin compilation and `:app:assembleDebug` passed; no tests run. Manual verification remains for both layouts, route-less and photo activities, preview dismissal, selected stretch preservation, and offline operation.
