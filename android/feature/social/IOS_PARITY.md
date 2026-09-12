# Social iOS Parity

## Authority

- iOS home and feed: `ios/Outbound/Outbound/Domains/Social/SocialHomeView.swift`
- iOS connection QR flow: `ios/Outbound/Outbound/Domains/Social/ConnectionQRCodeViews.swift`
- iOS Circle surfaces: `ios/Outbound/Outbound/Domains/Social/CircleViews.swift`
- Android home: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialScreen.kt`
- Android connection QR flow: `src/main/kotlin/com/plainstride/outbound/feature/social/ConnectionQrScreens.kt`
- Android avatar loading: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialAvatar.kt`

## Home Surface

- The Social root has no leading page title; global conditions, community, and notification actions remain trailing controls.
- Connections, Your Circle, Upcoming, Past activities, Groups, and Recent activity share the iOS section-label, rounded-card, spacing, and action hierarchy.
- Connections preserve a footprint-matched initial placeholder, accepted-person previews, active-workout indicators, and a dedicated full-screen list/search surface.
- Incoming requests render as tappable requester profile cards on Social home and in Connections, with separate icon-only Accept and Decline actions; the requester profile retains both labeled actions.
- Empty, invitation, Circle creation, event, Group, recognition, and feed states use the same standard or companion card role as iOS.
- Feed cards remain map-first with overlaid stats and Cheer, comment, profile, and safety actions. Tapping anywhere else on an activity card opens its detail page. Route previews use the shared Google map renderer as a non-interactive snapshot-like surface with gestures, map chrome, and endpoint markers disabled, matching the iOS `interactionModes: []` presentation.

## Personal QR Connection Flow

- Me's profile card exposes a dedicated personal QR action that opens the generator directly, matching the iOS profile-card journey without routing through Connections first.
- Connections' add menu matches iOS with Scan QR code, Show my QR code, and Invite by link actions.
- The personal QR screen concurrently loads the signed-in profile and the opaque backend connection link, renders only the canonical URL, and provides loading and unavailable states.
- The scanner uses CameraX with the established ZXing decoder, accepts only `https://run.plainstride.com/connect/:code`, pauses during request submission, and maps self, duplicate, incoming, existing, success, invalid, and retryable failure results to transient localized feedback.
- CameraX startup is cancellable without treating normal Compose lifecycle restarts as camera failures, clears stale app-owned camera use cases, prefers the rear camera, and falls back to the front camera on devices that expose only one front-facing camera.
- Verified `/connect/:code` Android App Links resolve the opaque code without mutation, route to the owner's Social profile, and expose Connect or the current relationship action there. Only an explicit Connect tap sends a request and emits `connection_qr_code_request_result`; profile opening emits `social_profile_opened` with `entry_source = connection_qr_code`.
- Camera first-use permission, denied-with-Settings recovery, and unavailable-hardware states match the corresponding iOS information hierarchy.
- Invite by link uses Android's native share sheet with one localized plain-text referral invitation, matching iOS `SystemSharePresenter` behavior.

## Shared Resources And Accessibility

- Copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings` for English, Spanish, and Simplified Chinese.
- Icon actions provide semantic labels and at least 48 dp touch targets.
- Avatars use the application-wide `OkHttpClient`, follow the backend redirect, cache decoded images, coalesce in-flight URL requests, and retain an initials fallback.

## Verification Scenarios

- Initial loading, empty connections, accepted connections, active-workout presence, Circle empty/list/invitation, upcoming/past empty/list, Groups, empty/populated feed, and avatar success/fallback.
- Light/dark themes, supported locales, font scaling, and TalkBack traversal remain manual device checks.
- QR loading/success/failure, camera first use/denial/unavailable, invalid payload, self-scan, duplicate/existing relationship, success, and offline retry remain manual device checks.

## Status And Exceptions

- Home presentation and avatar delivery are aligned with the current iOS implementation.
- Circle creation is a full-screen, multi-select flow with optional naming and account-timezone creation. Circle detail now includes weekly progress, member contribution and recent-workout context, preset Cheers, focus/skip controls, invitations, primary selection, notification muting, rename, member removal, leave, archive, and reactivation operations.
- Android uses a full-screen Compose dialog for Connections because the current feature module does not yet own a nested navigation graph; this preserves the iOS information hierarchy and back behavior without a platform-visible modal card.
- Android uses full-screen Compose dialogs for the personal QR and scanner destinations for the same navigation-ownership reason. CameraX plus ZXing replaces VisionKit while preserving the accepted payload and submission contract.
- Broader Social journey items outside this focused home-polish change remain tracked by `docs/android-social-parity-prompt.md` and must not be considered complete based on this manifest.

## Circle Reference Scenarios

- No Circle with accepted connections, creation with one or several invitees, generated or custom name, awaiting-members state, active progress with and without a numeric focus, personal skip, shared focus now/next week, owner/member management, archived/reactivated lifecycle, and transient mutation failure.
