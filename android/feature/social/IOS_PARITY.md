# Social iOS Parity

## Authority

- iOS home and feed: `ios/Outbound/Outbound/Domains/Social/SocialHomeView.swift`
- iOS connection QR flow: `ios/Outbound/Outbound/Domains/Social/ConnectionQRCodeViews.swift`
- iOS Group surfaces: `ios/Outbound/Outbound/Domains/Social/GroupViews.swift`
- Android home: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialScreen.kt`
- Android connection QR flow: `src/main/kotlin/com/plainstride/outbound/feature/social/ConnectionQrScreens.kt`
- Android avatar loading: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialAvatar.kt`

## Home Surface

- Social uses a persistent, text-only Feed, People, Groups, and Routes selector at the top of the page, matching iOS placement. The 44 dp row includes selected-state color, accessible labels, action badges, and parity tab analytics. A runner without accepted connections lands on People; otherwise Social opens Feed. An explicit tab choice remains selected while the task stays alive.
- The Social root has no leading page title; global conditions, community, and notification actions remain trailing controls.
- Feed mirrors the iOS `Active now`, prioritized Upcoming carousel, and paginated Activity Feed order. Activity cards use the iOS 1.5:1 route preview, stats overlay, milestone and photo-count badges, profile and safety actions, Cheers with cheerer avatars/list, comments, and activity-detail navigation. People owns inline search, incoming requests, and the accepted-connection list, with Connections opening the existing full search, QR, referral, blocked-account, and pagination destination. Groups owns invitations and joined Group cards with first-Group creation. Routes provides a direct entry into the existing community route library.
- The Notification Center action uses the shared unread count in a high-contrast numeric badge rather than a low-visibility dot.
- Connections, Your groups, Upcoming, Past activities, Groups, and Recent activity share the iOS section-label, rounded-card, spacing, and action hierarchy.
- Connections preserve a footprint-matched initial placeholder, accepted-person previews, active-workout indicators, and a dedicated full-screen list/search surface.
- Incoming requests render as tappable requester profile cards on Social home and in Connections, with separate icon-only Accept and Decline actions; the requester profile retains both labeled actions.
- Empty, invitation, Group creation, event, Group, recognition, and feed states use the same standard or companion card role as iOS.
- Feed cards remain map-first with overlaid stats and Cheer, comment, profile, and safety actions. Tapping anywhere else on an activity card opens its detail page. Route previews use the shared Google map renderer as a non-interactive snapshot-like surface with gestures, map chrome, and endpoint markers disabled, matching the iOS `interactionModes: []` presentation.
- Activity feed stats use the account's distance and pace preference, preserve the route aspect ratio, show milestone and localized photo-count badges, pull to refresh, and load additional pages as the last card approaches with the same bounded analytics dimensions as iOS. A failed page load offers an inline retry action.
- Activity detail keeps the full route map visible behind a draggable, persistent sheet with collapsed, split, and expanded positions. The map camera inset follows the sheet height while it moves. Content order mirrors iOS: milestones, author/profile, caption and Cheer/comments, then the title/photo/stat hero, expandable splits, and companion prompt. Cheers show the matching heart action, overlapping cheerer avatars/count, and a full cheerer list with profile links. Photo thumbnails use a bottom gradient caption and selected-photo outline; photo metadata and media continue to load independently, so photos without coordinates remain available without creating map pins.
- The activity owner can open the existing share-card preview from detail and save or share it. Detail, split, photo, and share actions use the shared activity analytics contract with `social_feed` as the source.

## Personal QR Connection Flow

- Me's profile card exposes a dedicated personal QR action that opens the generator directly, matching the iOS profile-card journey without routing through Connections first.
- Connections' add menu matches iOS with Scan QR code, Show my QR code, and Invite by link actions.
- The personal QR screen concurrently loads the signed-in profile and the opaque backend connection link, renders only the canonical URL, and provides loading and unavailable states.
- The scanner uses CameraX with the established ZXing decoder, accepts canonical `https://plainstride.ai/invite/r/:code` and compatible `/connect/:code` URLs, closes after a valid scan, and resolves the shared personal code through the same profile flow as an Android App Link.
- CameraX startup is cancellable without treating normal Compose lifecycle restarts as camera failures, clears stale app-owned camera use cases, prefers the rear camera, and falls back to the front camera on devices that expose only one front-facing camera.
- Verified `/connect/:code` Android App Links resolve the opaque code without mutation, route to the owner's Social profile, and expose Connect or the current relationship action there. Only an explicit Connect tap sends a request and emits `connection_qr_code_request_result`; profile opening emits `social_profile_opened` with `entry_source = connection_qr_code`.
- Camera first-use permission, denied-with-Settings recovery, and unavailable-hardware states match the corresponding iOS information hierarchy.
- Invite by link uses Android's native share sheet with one localized plain-text referral invitation, matching iOS `SystemSharePresenter` behavior.

## Shared Resources And Accessibility

- Copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings` for English, Spanish, and Simplified Chinese.
- Icon actions provide semantic labels and at least 48 dp touch targets.
- Avatars use the application-wide `OkHttpClient`, follow the backend redirect, cache decoded images, coalesce in-flight URL requests, and retain an initials fallback.
- Social feature-tab labels and the Routes entry description are sourced from the shared localization catalog for English, Spanish, and Simplified Chinese. Tab selections use the shared `social_tab_selected` analytics event with a bounded tab value and `tab_row` entry source.

## Verification Scenarios

- Initial loading, empty connections, accepted connections, active-workout presence, Group empty/list/invitation, upcoming/past empty/list, Groups, empty/populated feed, and avatar success/fallback.
- Activity feed active-runner ordering and profile navigation, prioritized upcoming events, empty/loading/populated states, refresh and pagination/retry, preference units, card route/stat overlays, milestones, photos, Cheers and cheerer-list/profile navigation, comments, report/block/delete, and activity-detail entry. Activity detail with and without photos, optional metrics, splits, missing photo coordinates, collapsed/split/expanded sheet drag with map resizing, photo captions and selection, and owner share preview.
- Light/dark themes, supported locales, font scaling, and TalkBack traversal remain manual device checks.
- QR loading/success/failure, camera first use/denial/unavailable, invalid payload, self-scan, duplicate/existing relationship, success, and offline retry remain manual device checks.

## Status And Exceptions

- The top-level four-destination Social navigation and destination ownership are implemented. Feed and Groups content are aligned to their iOS information hierarchy; People discovery retains the existing full Connections destination for QR, referral, blocks, and paginated search.
- Android Routes opens the existing community route library as a full destination instead of embedding that library under the Social tab. This is an Android navigation limitation and is the remaining visible difference in the feature selector.
- Activity feed and detail behavior follow the iOS social surface, using the shared Android activity share-card renderer and localized copy. Android's `Active now` entries open profiles; iOS can open Live Cheer when an active live session exists, and Android has no matching live Cheer screen yet.
- Group creation offers two server-backed templates. Group detail renders policy-specific capabilities, notices, events, membership, and management operations from the unified Group contract.
- Android uses a full-screen Compose dialog for Connections because the current feature module does not yet own a nested navigation graph; this preserves the iOS information hierarchy and back behavior without a platform-visible modal card.
- Android uses full-screen Compose dialogs for the personal QR and scanner destinations for the same navigation-ownership reason. CameraX plus ZXing replaces VisionKit while preserving the accepted payload and submission contract.
- Remaining Social differences and manual reference checks remain tracked by `docs/android-social-parity-prompt.md`; this manifest records the current tab navigation and its Routes navigation exception.

## Group Reference Scenarios

- No Group with accepted connections, creation with one or several invitees, generated or custom name, awaiting-members state, active progress with and without a numeric focus, personal skip, shared focus now/next week, owner/member management, archived/reactivated lifecycle, and transient mutation failure.
