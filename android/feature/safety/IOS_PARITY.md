# Safety And Live Following iOS Parity

## Authority

- iOS follower UI and recording: `ios/Outbound/Outbound/Safety/LiveCheerView.swift`
- iOS sharing lifecycle: `ios/Outbound/Outbound/Safety/LiveShareStore.swift`
- Android follower UI: `src/main/kotlin/com/plainstride/outbound/feature/safety/LiveCheerFollowerScreen.kt`
- Android sharing lifecycle: `src/main/kotlin/com/plainstride/outbound/feature/safety/LiveShareCoordinator.kt`

## Live Following

- `liveCheerInvitation` notifications route to the recipient-authorized follower endpoint rather than the owner safety-share endpoint.
- The follower page refreshes every five seconds while active and shows the privacy-authorized route, distance, elapsed time, heart rate, and current pace while active or average pace after the activity ends. Distance and pace follow the selected measurement units.
- Press-and-hold microphone recording sends an AAC/MPEG-4 Cheer capped at 15 seconds. Permission, load, and send results are localized in English, Spanish, and Simplified Chinese and use transient Snackbar feedback.
- Voice recording is available only when the runner's session enables voice Cheers; otherwise explain that the runner needs Plainstride Plus. Show the follower's latest Sent, Delivered, Heard, or acknowledged receipt state.
- While recording, the runner polls for pending Cheers and plays original audio through navigation-guidance audio routing. Mark a Cheer heard only after playback succeeds, then offer a dismissible banner and explicit `❤️ Heard you` acknowledgment.
- Analytics record follower entry source and bounded send success/failure only; audio, identities, session IDs, locations, and metrics are excluded.

## Cheer invitation setup

- Recording setup opens a full-height invitation picker. Accepted connections are listed with trusted contacts first, followed by other connections.
- Trusted contacts are selected automatically when there is no saved selection. The runner can toggle any accepted connection, and Done arms only the selected recipients for the next activity; an empty selection turns sharing off.
- When there are no trusted contacts, show the trusted-contact setup link. Explain that invitees can see precise location, pace, distance, and heart rate for the activity and can send short in-app voice Cheers.
- Record only the bounded participant-count bucket when invitation choices are saved. Do not include recipient IDs or names.

## Verification Scenarios

- Active, ended, missing/unauthorized, initial-loading, refresh-failure, route-present, route-empty, metric-missing, metric/imperial, entitlement-locked, all Cheer receipt states, microphone-granted, microphone-denied, record-release, send-failure, playback-failure, and runner acknowledgment states.
- TalkBack labels, 48 dp controls, light/dark themes, supported locales, and font scaling remain manual device checks.
