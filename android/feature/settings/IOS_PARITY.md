# Me And Settings iOS Parity

## Authority And Counterparts

- iOS Me and Settings: `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift` (`SimplifiedMeView`, `SimplifiedSettingsView`, and `SimplifiedProfileView`).
- Android route and state: `MeRoute.kt`, `SettingsViewModel.kt`, and `SettingsRepository.kt`.
- Android feature destinations are composed by `PlainstrideApp.kt` for Progress, routes, Health Connect, Safety, notifications, reminders, live guidance, and music.

## States And Transitions

- Me presents profile identity, current focus, this-week progress, and recent activities in the same card hierarchy as iOS. Recent activities use one compact 20dp-radius card with the section label and Add, Health Connect import, and All actions in its header instead of separate section, activity, and history cards.
- Profile identity renders the account avatar when available, with initials as an offline/error fallback. This-week totals fall back to the local activity repository while planning data is unavailable.
- Profile editing, refresh, settings, and activity history remain reachable with cached content visible while refresh is in progress.
- Settings groups account, reminders, safety, live guidance, appearance, units, health, gear/progress, integrations, photos, legal/help, debug replay, version, and deletion using Android-native destinations. Saving activity photos to the device's `Pictures/Plainstride` album is enabled by default and runs only after the activity is durably stored.
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

- Core Me hierarchy, profile editing, Connections preview, current focus, My Routes, learned insights, weekly summary, Milestones, iOS-aligned recent activity actions and compact rows, settings/preferences, integrations, legal links, sign-out, and deletion are implemented.
- Settings exposes planned-workout reminders and Safety as named sections matching the iOS hierarchy instead of burying them among integrations.
- Deterministic visual-reference captures remain open parity work.

## Platform Substitutions

- Health Connect replaces Apple Health; Spotify and Android media integrations replace Apple Music where applicable.
- Google identity plus the one-time iPhone transfer flow replaces Apple sign-in while preserving one Plainstride account.
