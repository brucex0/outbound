# Safety And Live Following iOS Parity

## Authority

- iOS follower UI and recording: `ios/Outbound/Outbound/Safety/LiveCheerView.swift`
- iOS sharing lifecycle: `ios/Outbound/Outbound/Safety/LiveShareStore.swift`
- Android follower UI: `src/main/kotlin/com/plainstride/outbound/feature/safety/LiveCheerFollowerScreen.kt`
- Android sharing lifecycle: `src/main/kotlin/com/plainstride/outbound/feature/safety/LiveShareCoordinator.kt`

## Live Following

- `liveCheerInvitation` notifications route to the recipient-authorized follower endpoint rather than the owner safety-share endpoint.
- The follower page refreshes every five seconds while active and shows the privacy-authorized route, last runner position, distance, pace, heart rate, and ended state.
- Press-and-hold microphone recording sends an AAC/MPEG-4 Cheer capped at 15 seconds. Permission, load, and send results are localized in English, Spanish, and Simplified Chinese and use transient Snackbar feedback.
- Analytics record follower entry source and bounded send success/failure only; audio, identities, session IDs, locations, and metrics are excluded.

## Verification Scenarios

- Active, ended, missing/unauthorized, initial-loading, refresh-failure, route-present, route-empty, metric-missing, microphone-granted, microphone-denied, record-release, and send-failure states.
- TalkBack labels, 48 dp controls, light/dark themes, supported locales, and font scaling remain manual device checks.
