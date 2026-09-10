# Social iOS Parity

## Authority

- iOS home and feed: `ios/Outbound/Outbound/Domains/Social/SocialHomeView.swift`
- iOS Circle surfaces: `ios/Outbound/Outbound/Domains/Social/CircleViews.swift`
- Android home: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialScreen.kt`
- Android avatar loading: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialAvatar.kt`

## Home Surface

- The Social root has no leading page title; global conditions, community, and notification actions remain trailing controls.
- Connections, Your Circle, Upcoming, Past activities, Groups, and Recent activity share the iOS section-label, rounded-card, spacing, and action hierarchy.
- Connections preserve a footprint-matched initial placeholder, accepted-person previews, active-workout indicators, and a dedicated full-screen list/search surface.
- Empty, invitation, Circle creation, event, Group, recognition, and feed states use the same standard or companion card role as iOS.
- Feed cards remain map-first with overlaid stats and Cheer, comment, profile, and safety actions.

## Shared Resources And Accessibility

- Copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings` for English, Spanish, and Simplified Chinese.
- Icon actions provide semantic labels and at least 48 dp touch targets.
- Avatars use the application-wide `OkHttpClient`, follow the backend redirect, cache decoded images, coalesce in-flight URL requests, and retain an initials fallback.

## Verification Scenarios

- Initial loading, empty connections, accepted connections, active-workout presence, Circle empty/list/invitation, upcoming/past empty/list, Groups, empty/populated feed, and avatar success/fallback.
- Light/dark themes, supported locales, font scaling, and TalkBack traversal remain manual device checks.

## Status And Exceptions

- Home presentation and avatar delivery are aligned with the current iOS implementation.
- Android uses a full-screen Compose dialog for Connections because the current feature module does not yet own a nested navigation graph; this preserves the iOS information hierarchy and back behavior without a platform-visible modal card.
- Broader Social journey items outside this focused home-polish change remain tracked by `docs/android-social-parity-prompt.md` and must not be considered complete based on this manifest.
