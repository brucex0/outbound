# Me And Settings iOS Parity

## Authority And Counterparts

- iOS Me and Settings: `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift` (`SimplifiedMeView`, `SimplifiedSettingsView`, and `SimplifiedProfileView`).
- Android route and state: `MeRoute.kt`, `SettingsViewModel.kt`, and `SettingsRepository.kt`.
- Android feature destinations are composed by `PlainstrideApp.kt` for Progress, routes, Health Connect, Safety, notifications, reminders, live guidance, and music.

## States And Transitions

- Me presents profile identity, current focus, this-week progress, and recent activities in the same card hierarchy as iOS.
- Profile editing, refresh, settings, and activity history remain reachable with cached content visible while refresh is in progress.
- Settings groups account, reminders, safety, live guidance, appearance, units, health, gear/progress, integrations, legal/help, debug replay, version, and deletion using Android-native destinations.
- Preference writes are local-first and report transient save or retry results through the app snackbar.
- Sign-out and permanent account deletion require confirmation; deletion clears account-scoped local data after server success.

## Resources, Analytics, And Accessibility

- Visible strings are localized in English, Spanish, and Simplified Chinese.
- Profile/settings controls retain 48dp targets, semantic button roles, headings, and non-color selection indicators.
- Refresh, preference, onboarding replay, legal, identity-link, sign-out, and deletion events use sanitized allowlisted values without profile or health content.

## Reference Scenarios

- New account with no plan or activities; cached/offline account; active plan with weekly progress; long activity history.
- Metric and imperial units, every appearance theme, increased font scale, and all supported locales.
- Sign-out cancellation, Google linking, profile validation, preference retry, and account deletion confirmation.

## Current Status

- Core Me hierarchy, profile editing, current focus, weekly summary, recent activity navigation, settings/preferences, integrations, legal links, sign-out, and deletion are implemented.
- Connections preview, recognition presentation, and deterministic visual-reference captures remain open parity work.

## Platform Substitutions

- Health Connect replaces Apple Health; Spotify and Android media integrations replace Apple Music where applicable.
- Google identity plus the one-time iPhone transfer flow replaces Apple sign-in while preserving one Plainstride account.
