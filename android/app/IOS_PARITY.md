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
- [ ] Direct tab presses and restored navigation have side-by-side evidence.
- [ ] Launcher motion, foreground restart, and reduced-motion behavior match iOS.
- [ ] Inbox action and unread badge appear on every primary screen.
- [ ] Fixed reference captures exist for every primary screen in supported themes, locales, and text sizes.

## Shared Resources

- Tab and assistant labels are generated from the canonical XCStrings catalog.
- Navigation and assistant symbols are native semantic icons; the shell owns no duplicate bitmap/vector assets.

## Analytics And Accessibility

- Authentication legal links emit `legal_document_opened` with the authentication entry source and never send the URL.
- Assistant opening emits `assistant_launcher_opened` with `destination` and `entry_source`.
- Navigation items and the assistant launcher expose generated localized labels.

## Platform Substitutions

- Compose Navigation replaces SwiftUI/UIKit tab coordination; the product topology remains identical.
