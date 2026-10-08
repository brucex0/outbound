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
- Feed mirrors the iOS `Active now`, prioritized Upcoming carousel, and paginated Activity Feed order. Activity cards use the iOS 1.5:1 route preview, stats overlay, milestone and photo-count badges, profile and safety actions, Cheers with cheerer avatars/list, comments, and activity-detail navigation. People owns inline search, incoming requests, and an eight-person accepted-connection preview; `All` appears only when the preview hides more connections or another connection page is available. Connections opens the full search, QR, referral, blocked-account, and cursor-paginated destination. That destination mirrors iOS Requests, Connections, and Sent sections, including canceling outgoing requests. Groups owns invitations and joined Group cards with first-Group creation.
- Routes embeds the community route library directly beneath the top selector.
- The Notification Center action uses the shared unread count in a high-contrast numeric badge rather than a low-visibility dot.
- Connections, Your groups, Upcoming, Past activities, Groups, and Recent activity share the iOS section-label, rounded-card, spacing, and action hierarchy.
- Connections preserve a footprint-matched initial placeholder, accepted-person previews, active-workout indicators, and a dedicated full-screen list/search surface. Its People-tab `All` action is not duplicated below the list, and the action is hidden when all accepted connections fit in the preview and there is no additional page.
- Connections navigation requests are consumed after opening the destination. The full-screen dialog is transient across top-level tab switches, so returning to Social or Me does not reopen a previously dismissed or abandoned Connections view. An actual Connections opening emits one `connections_opened` event with a bounded entry source.
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
- Open Connections from Me, leave it through a top-level tab, and switch between Social and Me; the dialog stays closed until Connections is explicitly opened again. Repeat after a notification or deep link opens Connections.
- Activity feed active-runner ordering and profile navigation, prioritized upcoming events, empty/loading/populated states, refresh and pagination/retry, preference units, card route/stat overlays, milestones, photos, Cheers and cheerer-list/profile navigation, comments, report/block/delete, and activity-detail entry. Activity detail with and without photos, optional metrics, splits, missing photo coordinates, collapsed/split/expanded sheet drag with map resizing, photo captions and selection, and owner share preview.
- Light/dark themes, supported locales, font scaling, and TalkBack traversal remain manual device checks.
- QR loading/success/failure, camera first use/denial/unavailable, invalid payload, self-scan, duplicate/existing relationship, success, and offline retry remain manual device checks.

## Status And Exceptions

- The top-level four-destination Social navigation and destination ownership are implemented. Feed and Groups content are aligned to their iOS information hierarchy; People discovery retains the full Connections destination for QR, referral, blocks, Requests, Connections, Sent, and cursor pagination.
- The Social Routes tab uses the iOS embedded discovery hierarchy: inline search and submit, nearby and import actions, imported-route and community sections, matching empty/loading copy, and route rows. Its reusable community library remains available to the separate route destination. Community route details and imported-route previews stay within Social while open.
- Activity feed and detail behavior follow the iOS social surface, using the shared Android activity share-card renderer and localized copy. Android's `Active now` entries open profiles; iOS can open Live Cheer when an active live session exists, and Android has no matching live Cheer screen yet.
- Group creation offers matching private-circle and open-community choices with the shared Group mark, explicit invite/join access, and distinct template-specific setup introductions. Public Groups accept an optional base city, which is shown in discovery and detail. The create action remains in progress until the server responds; success opens the created Group, while failure keeps the form available for retry and shows transient feedback. The community template is public and open to join on both platforms. Group detail renders policy-specific capabilities, notices, events, membership, and management operations from the unified Group contract.
- Group detail is a full-screen destination rather than a modal overlay. It follows the iOS content order: shared identity card; community join/about/notices/events/member controls, or private events/theme/members/invitations/moments/history. Android's group projection now decodes the event, moment, history, next-theme, and pending-request data needed to render those sections. Notice publishing and read state use the same group endpoints as iOS. Selecting a private Group's Up Next card opens the full-screen scheduled-activity detail with matching event facts, in-person or virtual RSVP, organizer invite action, and `activity_event_detail_opened` source `group_up_next`.
- The Groups tab refreshes when opened, maps the API's `membershipRole` summary field, and preserves the last cached Social home when the separate Groups request fails, instead of replacing visible Groups with an empty list.
- The public Group directory follows server cursors so later pages remain discoverable. Non-members see the aggregate member count without member identities; active members see the member list. Owner identity remains authoritative for membership controls.
- Android uses a full-screen Compose dialog for Connections because the current feature module does not yet own a nested navigation graph; this preserves the iOS information hierarchy and back behavior without a platform-visible modal card.
- Android uses full-screen Compose dialogs for the personal QR and scanner destinations for the same navigation-ownership reason. CameraX plus ZXing replaces VisionKit while preserving the accepted payload and submission contract.
- Remaining Social differences and manual reference checks remain tracked by `docs/android-social-parity-prompt.md`; the top-level selector remains text-only and all four tabs switch content in place. Group detail spacing, theme variants, and accessibility traversal still need manual device comparison.

## Group Reference Scenarios

- No Group with accepted connections, creation loading/success/failure with one or several invitees, generated or custom name, awaiting-members state, active progress with and without a numeric focus, personal skip, shared focus now/next week, owner/member management, archived/reactivated lifecycle, and transient mutation failure.
