# App Shell iOS Parity

## Authority And Mapping

- iOS login: `ios/Outbound/Outbound/App/AuthView.swift`
- iOS shell: `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`
- iOS session owner: `ios/Outbound/Outbound/App/MainTabView.swift`
- Android shell: `android/app/src/main/kotlin/com/plainstride/outbound/PlainstrideApp.kt`
- Android session owner: `ActiveRecordingViewModel` plus the recording route/service

## Contract

- [x] Signed-out presentation carries the same brand story, companion positioning, provider explanation, and legal destinations; Google is the Android-native identity provider.
- [x] Existing iPhone accounts can enter the deliberate one-time transfer/link flow without weakening normal Google sign-in.
- [x] Primary navigation contains exactly Social, Today, and Me.
- [x] Today is initially selected.
- [x] Assistant is a persistent launcher on every primary destination, not a fourth tab.
- [x] Closing Assistant returns to the primary destination that opened it.
- [x] Assistant deep links open the same destination.
- [x] Recording is full-screen and hides primary navigation.
- [x] A live, paused, or awaiting-save session is restored directly into the recording surface instead of leaving Today in a non-startable state.
- [x] The shell-owned bottom row clears gesture and three-button system navigation insets.
- [ ] Direct tab presses and restored navigation have side-by-side evidence.
- [ ] Launcher motion, foreground restart, and reduced-motion behavior match iOS.
- [ ] Inbox action and unread badge appear on every primary screen.
- [ ] Fixed reference captures exist for every primary screen in supported themes, locales, and text sizes.

## Shared Resources

- Tab and assistant labels are generated from the canonical XCStrings catalog.
- Tab symbols remain native semantic icons; the persistent assistant uses the shared fox-head image, and the launcher uses the shared running-fox artwork from `shared-resources/icons/source`.

## Analytics And Accessibility

- Authentication legal links emit `legal_document_opened` with the authentication entry source and never send the URL.
- Assistant opening emits `assistant_launcher_opened` with `destination` and `entry_source`.
- Opening the notification inbox emits `notification_inbox_opened`; unread state clears locally when the inbox becomes visible and is synchronized through the read-all endpoint.
- Navigation items and the assistant launcher expose generated localized labels.

## Platform Substitutions

- Compose Navigation replaces SwiftUI/UIKit tab coordination; the product topology remains identical.

## Connectivity

- iOS authority: `ios/Outbound/Outbound/Core/ConnectivityStore.swift`, `ios/Outbound/Outbound/App/MainTabView.swift`, and the activity status in `ios/Outbound/Outbound/Camera/CameraHUDView.swift` and `Activity/RecordView.swift`.
- Android counterpart: `connectivity/NetworkConnectivityMonitor.kt`, `ConnectivityViewModel.kt`, the signed-in shell in `PlainstrideApp.kt`, and `feature/recording/RecordingScreen.kt`.
- The app observes Android network availability and displays the localized offline capsule inline above signed-in screen content. After reconnection, pending activity writes stay in the account's local outbox and receive transient Snackbar feedback, without shifting screen content.
- Reconnection schedules the existing unique WorkManager activity-sync job. The active recording route hides the shell capsule and shows an activity-specific offline status instead.
- Network status is environmental and has no corresponding iOS analytics event. Offline and recording statuses expose localized accessibility labels; the pending-sync Snackbar uses localized text.

### Reference Scenarios

- Online with no pending writes; airplane mode while on Today, Social, Me, and nested signed-in screens; restore connectivity with queued activity writes and confirm transient feedback; drain the outbox.
- Begin and continue an activity offline; restore connectivity and confirm local recording remains active while sync resumes.
- English, Spanish, and Simplified Chinese; light/dark themes; TalkBack announcement of offline and pending-sync states.

### Status

- Connectivity monitoring, offline and recording banners, transient pending-sync feedback, account-scoped pending outbox visibility, and reconnect scheduling are implemented. Manual airplane-mode and TalkBack validation remain device checks.
