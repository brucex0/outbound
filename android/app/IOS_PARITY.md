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
- [x] Entity pages use independent ID-based routes, without inserting Social/History/library hosts. Connections is shared across all callers; `connections_opened` retains its bounded entry source. See `docs/android-navigation.md`.
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
- Tab symbols remain native semantic icons; the persistent assistant uses the shared fox-head image. The Android launcher uses the shared running fox as a transparent, inset adaptive-icon foreground over its solid evergreen background.

## Analytics And Accessibility

- Login keeps the email-use explanation off the welcome screen, gives the “Better together” badge 24 dp of space before the companion copy, and embeds underlined legal links in the localized acceptance sentence.
- The Google button shows signing-in progress only for `AuthOperation.SignIn`; sign-out, deletion, linking, and transfer cleanup retain the normal provider label and existing operation guards. Sign-out analytics remain `auth_sign_out`.
- Authentication legal links emit `legal_document_opened` with the authentication entry source and never send the URL.
- Assistant opening emits `assistant_launcher_opened` with `destination` and `entry_source`.
- The fox tilts subtly after 20 seconds, then at 30-second intervals; it no longer loops a bounce, sparkle, or glow. Disabled system animations keep it static. A separate, localized envelope target opens the durable Notification Center; the fox itself always opens Assistant.
- Fresh unread Needs You items take priority over cheers/milestones for one brief delivery preview per local day and account. Routine updates use only the envelope. The existing notification presentation policy owns ranking and aggregation; previews dispatch through the same destination mapper as inbox rows. Preview delivery/dismissal does not mark records read or resolve actions. Opening Notification Center retains its existing read-all behavior.
- Delivery receipts are persisted per account/event only after the launcher is laid out in a focused, resumed shell and removed for that account on deletion. Events older than 24 hours, live-cheer invitations at least eight hours old, and malformed/future timestamps do not request attention; receipts outlive the freshness window. Tab changes, foregrounding, and relaunch cannot replay the same delivery. Activity routes and modal windows suppress gestures/previews without consuming a new receipt. Previews use a seven-second base timeout and honor Android's accessibility time-to-act setting.
- The existing successful-save celebration/stretch header includes one brief fox reaction. History loads, imports, failed saves, and ordinary shell returns cannot trigger it. It reuses the shared fox asset in `core/designsystem`.
- Presence analytics use `feature_exposed` with `feature=fox_companion_presence` and `result=idle|delivery|celebration`. Delivery controls use `fox_companion_action_selected` with `selection_type=notification_preview|notification_dismissed|envelope_opened`; previews also retain inbox action analytics. Events exclude message text, actors, account/event IDs, and activity details; idle analytics fire once per launcher appearance rather than each gesture.
- Compose test tags are `fox-companion-launcher`, `fox-companion-envelope`, `fox-companion-preview`, `fox-companion-preview-open`, `fox-companion-preview-dismiss`, and `fox-companion-celebration`. The launcher additionally publishes a non-spoken `FoxCompanionState` semantic value (`idle|delivery`).
- Opening the notification inbox emits `notification_inbox_opened`; unread state clears locally when the inbox becomes visible and is synchronized through the read-all endpoint.
- Navigation items and the assistant launcher expose generated localized labels.

## Platform Substitutions

- Compose Navigation replaces SwiftUI/UIKit tab coordination; the product topology remains identical.

## Connectivity

- iOS authority: `ios/Outbound/Outbound/Core/ConnectivityStore.swift`, `ios/Outbound/Outbound/App/MainTabView.swift`, and the activity status in `ios/Outbound/Outbound/Camera/CameraHUDView.swift` and `Activity/RecordView.swift`.
- Android counterpart: `connectivity/NetworkConnectivityMonitor.kt`, `ConnectivityViewModel.kt`, the signed-in shell in `PlainstrideApp.kt`, and `feature/recording/RecordingScreen.kt`.
- The app observes Android network availability and displays the localized offline capsule inline above signed-in screen content. After reconnection, pending activity writes stay in the account's local outbox and receive transient Snackbar feedback, without shifting screen content.
- Reconnection schedules the existing unique WorkManager activity-sync job. The active recording route hides the shell capsule and shows an activity-specific offline status instead.
- Default-network callbacks own connectivity after the initial snapshot. Availability/capability events update state directly; loss applies only to the tracked default network, avoiding stale synchronous reads during handover. `PlainstrideConnectivity` logs state changes without network identifiers.
- Network status is environmental and has no corresponding iOS analytics event. Offline and recording statuses expose localized accessibility labels; the pending-sync Snackbar uses localized text.

### Reference Scenarios

- Execute the navigation matrix in `docs/android-navigation.md`, including Me/Trusted Contacts → Connections, profiles and nested posts, personal activity details, route details, notifications/links, and recreation. Record actual device coverage separately.

- Online with no pending writes; airplane mode while on Today, Social, Me, and nested signed-in screens; restore connectivity with queued activity writes and confirm transient feedback; drain the outbox.
- Begin and continue an activity offline; restore connectivity and confirm local recording remains active while sync resumes.
- English, Spanish, and Simplified Chinese; light/dark themes; TalkBack announcement of offline and pending-sync states.

### Status

- Connectivity monitoring, offline and recording banners, transient pending-sync feedback, account-scoped pending outbox visibility, and reconnect scheduling are implemented.
- Verified on the connected S22 (2026-11-03): updated debug build has no offline banner on validated Wi-Fi with successful API responses; disabling Wi-Fi/mobile data shows the banner and restoring both clears it, with matching connectivity diagnostics. Build-only `:app:assembleDebug` passed; no test suite ran. Pending-outbox draining, active recording, airplane-mode, and TalkBack scenarios remain unverified.
