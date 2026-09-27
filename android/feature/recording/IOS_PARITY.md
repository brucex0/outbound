# Recording iOS Parity

## Authority And Counterparts

- iOS root and state handoff: `ios/Outbound/Outbound/Activity/RecordView.swift`
- iOS map and camera workout panels: `ios/Outbound/Outbound/Activity/LiveMapView.swift` and `ios/Outbound/Outbound/Camera/CameraHUDView.swift`
- iOS recorder, location, journal, and Live Activity: `ActivityRecorder.swift`, `LocationManager.swift`, `ActiveSessionJournal.swift`, and `SessionLiveActivityManager.swift`
- Android route and UI: `RecordingScreen.kt` and `RecordingViewModel.kt`
- Android process owner, location, and journal: `RecordingService.kt`, `RecordingCoordinator.kt`, `FusedRecordingLocationSource.kt`, and the Room active-session journal

## States And Transitions

- Today launches the prepared activity directly into a cancelable, spoken countdown when Voice Guide is enabled.
- Outdoor activity start follows iOS preflight: explain location use before the system prompt, direct previously denied users to app settings, refresh authorization when returning from settings, and hold the start until a location fix is no older than 15 seconds and no less accurate than 80 meters. Indoor sessions bypass both gates. A lost permission or GPS fix during countdown blocks recording and returns to the matching permission or acquisition state.
- Active recording is non-dismissible. Pause reveals separate Resume and Finish controls; Finish requires confirmation.
- The map and camera share compact and expanded dashboard state. Tap or vertical drag changes state without dismissing the activity.
- The compact dashboard mirrors iOS's glanceable time / primary action / optional Finish / distance row; the expanded dashboard owns the title and status, goal hero, progress, metric cards, current workout step, route name, and labeled controls.
- The primary live metric follows the selected distance, time, calorie, structured-workout, or freestyle goal.
- Live distance, pace, elevation, target progress, and calorie estimates honor the runner's persisted measurement and weight preferences, matching the iOS formatter and estimator contracts.
- Capturing a photo keeps the live camera preview running and moves the result into a private thumbnail instead of replacing the workout surface.
- The live map opens on the runner, keeps native pan/zoom controls, renders the selected route and recorded trail separately, and does not continuously zoom out as new samples arrive.
- Recovery returns to the live surface paused; completion stays in the same route for reflection, local save, or confirmed discard. Confirmed discard waits for the recording service to reach idle before navigating away, preventing recovery from reopening the discarded activity.
- Finish remains disabled while required photo persistence is pending.
- Post-run review leads with the recorded route (or a non-route activity hero), overlays the close and Save controls like iOS, and follows with contextual motivation, core stats, optional perceived effort, and photo review.
- Save is disabled below the shared iOS threshold of five minutes or 500 meters; closing the review always requires destructive confirmation.

## Resources, Analytics, And Accessibility

- Visible strings use generated shared localization resources in `src/main/res`.
- Setup, start, pause, resume, finish, save eligibility, discard, surface, media, and dashboard-state events use the canonical sanitized iOS event names and Android platform property.
- Controls expose semantic labels, retain 48dp-or-larger primary targets, and do not rely on color alone.

## Reference Scenarios

- Outdoor starts with location not yet requested, denied once, permanently denied, revoked in app settings, approximate, and precise; fresh, stale, inaccurate, and unavailable GPS fixes; permission loss during countdown; and indoor start without location.
- Planned distance workout, manual free run, timed walk, calorie goal, structured workout, and followed route.
- Active and paused map/camera surfaces, compact and expanded dashboard, pending photo write, finish confirmation, recovery, and post-run review.
- English, Spanish, and Simplified Chinese; light/dark themes; compact phone and increased font scale.

## Current Status

- Core start/spoken countdown, foreground recording, pause/resume/finish, camera/map switching, in-session voice commands, route-aware live mapping, recovery, review, local save, and the iOS compact/expanded dashboard hierarchy are implemented.
- Visible live heart rate/steps, coach text, music controls, and group-run strips remain dependent on those data streams being exposed to the recording UI; their audio, wearable, music, and safety owners are implemented separately.
- Manual visual comparison and real-device longevity/background validation remain release-gate work.

## Approved Exceptions

- Android uses an ongoing foreground-service notification instead of ActivityKit. It owns equivalent active/paused status and Pause/Resume actions at the Android platform boundary.
