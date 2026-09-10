# Recording iOS Parity

## Authority And Counterparts

- iOS root and state handoff: `ios/Outbound/Outbound/Activity/RecordView.swift`
- iOS map and camera workout panels: `ios/Outbound/Outbound/Activity/LiveMapView.swift` and `ios/Outbound/Outbound/Camera/CameraHUDView.swift`
- iOS recorder, location, journal, and Live Activity: `ActivityRecorder.swift`, `LocationManager.swift`, `ActiveSessionJournal.swift`, and `SessionLiveActivityManager.swift`
- Android route and UI: `RecordingScreen.kt` and `RecordingViewModel.kt`
- Android process owner, location, and journal: `RecordingService.kt`, `RecordingCoordinator.kt`, `FusedRecordingLocationSource.kt`, and the Room active-session journal

## States And Transitions

- Today launches the prepared activity directly into a cancelable countdown.
- Active recording is non-dismissible. Pause reveals separate Resume and Finish controls; Finish requires confirmation.
- The map and camera share compact and expanded dashboard state. Tap or vertical drag changes state without dismissing the activity.
- The primary live metric follows the selected distance, time, calorie, structured-workout, or freestyle goal.
- Recovery returns to the live surface paused; completion stays in the same route for reflection, local save, or confirmed discard.
- Finish remains disabled while required photo persistence is pending.

## Resources, Analytics, And Accessibility

- Visible strings use generated shared localization resources in `src/main/res`.
- Setup, start, pause, resume, finish, save, discard, surface, media, and dashboard-state events use sanitized Android analytics properties.
- Controls expose semantic labels, retain 48dp-or-larger primary targets, and do not rely on color alone.

## Reference Scenarios

- Planned distance workout, manual free run, timed walk, calorie goal, structured workout, and followed route.
- Active and paused map/camera surfaces, compact and expanded dashboard, pending photo write, finish confirmation, recovery, and post-run review.
- English, Spanish, and Simplified Chinese; light/dark themes; compact phone and increased font scale.

## Current Status

- Core start/countdown, foreground recording, pause/resume/finish, camera/map switching, recovery, review, local save, and compact/expanded live dashboard are implemented.
- Manual visual comparison and real-device longevity/background validation remain release-gate work.

## Approved Exceptions

- Android uses an ongoing foreground-service notification instead of ActivityKit. It owns equivalent active/paused status and Pause/Resume actions at the Android platform boundary.
