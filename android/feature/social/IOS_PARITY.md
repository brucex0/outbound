# Social iOS Parity

## Authority

- iOS home and feed: `ios/Outbound/Outbound/Domains/Social/SocialHomeView.swift`
- iOS connection QR flow: `ios/Outbound/Outbound/Domains/Social/ConnectionQRCodeViews.swift`
- iOS Group surfaces: `ios/Outbound/Outbound/Domains/Social/GroupViews.swift`
- Android home: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialScreen.kt`
- Android connection QR flow: `src/main/kotlin/com/plainstride/outbound/feature/social/ConnectionQrScreens.kt`
- Android avatar loading: `src/main/kotlin/com/plainstride/outbound/feature/social/SocialAvatar.kt`

## Profile Connection Actions

- Profiles opened from feeds, groups, connections, or QR codes resolve relationship metadata against the loaded connections list instead of treating a share-safe author without metadata as unconnected.
- Accepted connections show visible Disconnect and Report actions. Disconnect requires confirmation and closes the profile only after success; Report requires a reason and submits a `user` report through the existing safety endpoint. Results use transient feedback.
- Actions reuse `social_connection_removed` and `social_content_reported` with only success/failure; person IDs and report reasons stay out of analytics.
- Manual reference checks: open the same accepted person from a feed, group member list, connections, and QR code; confirm no Connect action; cancel/confirm disconnect; submit a report and verify transient feedback; keep incoming accept/decline and unconnected Connect behavior.

## Home Surface

- Social uses a persistent, text-only Feed, People, Groups, and Routes selector at the top of the page, matching iOS placement. The 44 dp row includes selected-state color, accessible labels, action badges, and parity tab analytics. A runner without accepted connections lands on People; otherwise Social opens Feed. An explicit tab choice remains selected while the task stays alive.
- The Social root has no leading page title; global conditions, community, and notification actions remain trailing controls.
- Feed mirrors the iOS `Active now`, prioritized Upcoming carousel, and paginated Activity Feed order. Activity cards use the iOS 1.5:1 route preview, stats overlay, milestone and photo-count badges, profile and safety actions, Cheers with cheerer avatars/list, comments, and activity-detail navigation. People owns inline search, incoming requests, and an eight-person accepted-connection preview; `All` appears only when the preview hides more connections or another connection page is available. Connections opens the full search, QR, referral, blocked-account, and cursor-paginated destination. That destination mirrors iOS Requests, Connections, and Sent sections, including canceling outgoing requests. Groups owns invitations and joined Group cards with first-Group creation.
- Routes embeds the community route library directly beneath the top selector.
- The Notification Center action uses the shared unread count in a high-contrast numeric badge rather than a low-visibility dot.
- Connections, Your groups, Upcoming, Past activities, Groups, and Recent activity share the iOS section-label, rounded-card, spacing, and action hierarchy.
- Connections preserve a footprint-matched initial placeholder, accepted-person previews, active-workout indicators, and a dedicated full-screen list/search surface. Its People-tab `All` action is not duplicated below the list, and the action is hidden when all accepted connections fit in the preview and there is no additional page.
- Connections navigation requests are consumed after opening the destination. The full-screen dialog is transient across top-level tab switches, so returning to Social or Me does not reopen a previously dismissed or abandoned Connections view. An actual Connections opening emits one `connections_opened` event with a bounded entry source.
- The Social create menu's Add connection action opens a dedicated full-screen Connections dialog titled Add connection, focuses the people search field, and keeps the current Social tab underneath. The dialog retains Scan QR code, Show my QR code, and Invite by link actions. Opening it while already on People still presents the explicit add flow.
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
- Open Add connection from the Social create menu on Feed, People, Groups, and Routes. Confirm the dialog opens over the selected tab, identifies itself as Add connection, focuses search, and keeps the QR and invite actions available; repeat while People is already selected.
- Activity feed active-runner ordering and profile navigation, prioritized upcoming events, empty/loading/populated states, refresh and pagination/retry, preference units, card route/stat overlays, milestones, photos, Cheers and cheerer-list/profile navigation, comments, report/block/delete, and activity-detail entry. Activity detail with and without photos, optional metrics, splits, missing photo coordinates, collapsed/split/expanded sheet drag with map resizing, photo captions and selection, and owner share preview.
- Light/dark themes, supported locales, font scaling, and TalkBack traversal remain manual device checks.
- QR loading/success/failure, camera first use/denial/unavailable, invalid payload, self-scan, duplicate/existing relationship, success, and offline retry remain manual device checks.

## Status And Exceptions

- The top-level four-destination Social navigation and destination ownership are implemented. Feed and Groups content are aligned to their iOS information hierarchy; People discovery retains the full Connections destination for QR, referral, blocks, Requests, Connections, Sent, and cursor pagination.
- The Social Routes tab uses the iOS embedded discovery hierarchy: inline search and submit, nearby and import actions, imported-route and community sections, matching empty/loading copy, and route rows. Its reusable community library remains available to the separate route destination. Community route details and imported-route previews stay within Social while open.
- Activity feed and detail behavior follow the iOS social surface, using the shared Android activity share-card renderer and localized copy. `Active now` opens the existing Live Cheer follower destination only for an authorized active invited session belonging to that runner; otherwise it opens the profile, matching iOS. The badge and localized accessibility action distinguish these destinations.
- Group creation offers matching private-circle and open-community choices with the shared Group mark, explicit invite/join access, and distinct template-specific setup introductions. Public Groups accept an optional base city, which is shown in discovery and detail. The create action remains in progress until the server responds; success opens the created Group, while failure keeps the form available for retry and shows transient feedback. The community template is public and open to join on both platforms. Group detail renders policy-specific capabilities, notices, events, membership, and management operations from the unified Group contract.
- Group detail is a full-screen destination rather than a modal overlay. It follows the iOS content order: shared identity card; community join/about/notices/events/member controls, or private events/theme/members/invitations/moments/history. Android's group projection now decodes the event, moment, history, next-theme, and pending-request data needed to render those sections. Notice publishing and read state use the same group endpoints as iOS. Selecting a private Group's Up Next card opens the full-screen scheduled-activity detail with matching event facts, in-person or virtual RSVP, organizer invite action, and `activity_event_detail_opened` source `group_up_next`.
- The Groups tab refreshes when opened, maps the API's `membershipRole` summary field, and preserves the last cached Social home when the separate Groups request fails, instead of replacing visible Groups with an empty list.
- The public Group directory follows server cursors so later pages remain discoverable. Non-members see the aggregate member count without member identities; active members see the member list. Owner identity remains authoritative for membership controls.
- Android uses a full-screen Compose dialog for Connections because the current feature module does not yet own a nested navigation graph; this preserves the iOS information hierarchy and back behavior without a platform-visible modal card.
- Android uses full-screen Compose dialogs for the personal QR and scanner destinations for the same navigation-ownership reason. CameraX plus ZXing replaces VisionKit while preserving the accepted payload and submission contract.
- Remaining Social differences and manual reference checks remain tracked by `docs/android-social-parity-prompt.md`; the top-level selector remains text-only and all four tabs switch content in place. Group detail spacing, theme variants, and accessibility traversal still need manual device comparison.

## Group Invitation Preview

- `GroupInvitationPreviewScreen` follows `GroupInvitationPreviewView` for the content order, localized copy, disabled actions during submission, in-place acceptance, dismissal on decline, transient feedback, and revalidation after failure. The server preview and access rules are defined in `docs/run-groups.md`.
- Invite entry points carry the invitation ID when fetching Group detail. Both clients distinguish unavailable invitations from retryable loading failures and emit the same preview exposure, accepted/declined, and failure events.
- Build verification: backend TypeScript compile, iOS simulator build, Android debug app assembly. No test suite was run. Manual device comparison remains required to validate rendering and navigation in a live invitation.

## Group Member Actions

- Android member rows omit the heart/encouragement action. Member management retains its existing permission checks.
- Removed the member-cheer handler and its `group_cheer_sent` instrumentation; opening Members still emits `group_members_opened`. Existing cheer moments remain visible in Group history.

## Group Reference Scenarios

- No Group with accepted connections, creation loading/success/failure with one or several invitees, generated or custom name, awaiting-members state, active progress with and without a numeric focus, personal skip, shared focus now/next week, owner/member management, archived/reactivated lifecycle, and transient mutation failure.

- Group member invitations exclude existing members and recipients with pending invitations, using the latest open Group detail. Opening the picker emits feature_exposed with only feature = group_invite_picker; invitation outcomes retain group_invitation_sent. No identities or picker contents are recorded.

## Recent Moment Details

- Authority: iOS `GroupViews.momentDetails` and `GroupMomentResultsView`.
- Tapping a recent moment opens a full detail page; Back returns to the same Group. Rows use relative timestamps and type-specific icons; details show the title, Group name, and full localized date with short time.
- Cheers show the localized preset and sender/recipient only when both remain in the member projection. Weekly completions show the current theme/note only when the completion ID matches the current week; predefined theme titles use the iOS translations.
- Completed activity moments with an `event:` ID load the same results endpoint. Loading, retryable failure, collecting, empty, participant outcome, optional distance in preferred units, photos, and optional `h:mm:ss` duration match iOS order and conditions. A completed outcome without visible stats still says Finished.
- Photo previews use authenticated media downloads, 132 × 100 dp frames, center crop, 8 dp corners, EXIF-aware decoding capped at 720 pixels, and a bounded decoded-image cache. The backend controls which photos and stats are visible; no client reconstructs hidden results.
- Analytics match `group_moment_opened` and `group_moment_results_loaded`, with the same bounded properties and no identities, dates, stats, or media in events.
- Manual parity cases: each moment type; missing Cheer members; custom/predefined/unknown themes; old completion IDs; malformed event IDs; collecting/empty/results/error/retry; completed without stats; no-recording/waiting outcomes; metric/imperial; no photos, thumbnail/full-content fallback; cached/uncached rotated/mirrored/portrait photos; Back and locale/font scaling.

Verification for this change: debug app build passed; a temporary local-only preview on a physical Android phone showed localized date, imperial distance, duration, collecting state, no-recording, completed-without-stats, and waiting outcomes. No server data was created. Final code preserves the Group list state on Back. Photo orientation/cache, loading/failure/retry, other locales, font scaling, and side-by-side iOS visual equality were reviewed in code but were not verified on device. Temporary preview code was removed.
## Group Activity Participation And Attribution

- Canonical behavior: `docs/run-groups.md` → Recording Participation And Attribution. iOS authority: `GroupActivityAttributionView.swift`, `ActivityEventParticipationSync.swift`, `ActivityEventDetailView`, `LiveMapView`, and the camera overlay in `RecordView`.
- Today displays the first eligible scheduled-day/active Group event, including members without an RSVP. It opens the same shared destination and offers explicit live sharing. Group member start permission is independent of RSVP. Shared event destinations retain the same complete event screen as Social entry, with the scheduled-day/active start window, owner controls, attendance choice, explicit live sharing, and participant states.
- Start launches directly with the event sport/title/duration goal and no private workout steps. Actual recording activation queues participation; discarded recordings queue the no-recording outcome. Account-scoped intents survive app restarts and retry on app/recording foreground and Social refresh. Saved upload retains the event ID and server reconciliation.
- Camera/map show the collapsible participant panel; map pills and authorized pins use the existing live session. Selecting a located participant focuses their pin; the recenter action returns to the recorder. Unknown, waiting, stale, and departed locations keep distinct treatment. Invite-link sessions use the same map, location-publish, and finish path without accepting a different event's session.
- Feed and personal/shared details show the group indicator, permission-safe event/Group name, and sport-specific companions. Unknown/remote attendance uses neutral participation wording; names cap at two plus the remaining count. Missing/offline attribution keeps a generic indicator. Attribution navigates to the shared event destination.
- Shared Social/event/profile destinations use account-scoped app-level state, so attribution opened from Me/Today does not require an existing Social navigation entry. Background Today loading does not emit Social/feed exposure analytics.
- Reuse the established avatar loader and its authenticated URL/cache behavior. Solo route maps retain their previous marker, camera, route, and mascot defaults when no extra group markers are supplied.
- Analytics: `group_activity_presence_viewed` uses only a participant-count bucket; start/save `group_run_enabled` includes event-linked and live-group recordings. RSVP results use bounded source, join/leave, and success/failure, with toast feedback. No participant/event IDs, names, attendance, or coordinates enter analytics.

### Verification Of This Parity Update

- Build-only checks: `:app:assembleDebug` and `:app:compileReleaseKotlin`; no test suite.
- Manual emulator previews of production components: collapsed/expanded participant states, sharing control, in-person Run/Bike wording, mixed/unknown attendance with `+N`, generic offline attribution, English/Spanish/Chinese, and light/dark layout. The temporary preview is excluded from the shipped source.
- Diff review: capability allow/deny/missing fallback, scheduled/active/terminal start gates, account-scoped queue removal/retry, event-vs-invite session isolation, stopped-sharing pins, and additive solo-map defaults.
- Not exercised against live authenticated participants: cross-device realtime location, backend offline replay, and end-to-end event navigation. These remain runtime verification limits; no production data was changed.

## Active Now Presence And Refresh

- iOS authorities: `WorkoutPresenceController.swift`, `SocialHomeView.activeNowRail`, its selected/foreground refresh task, and `TogetherStore.refreshConnections(retainingLoadedPages:)`.
- Recording service presence starts immediately for active/recovered recordings and heartbeats every 60 seconds, including pauses and background recording. Finish, discard, and service teardown cancel the heartbeat and then delete its presence. Each presence lifecycle has a fresh UUID so a delayed delete cannot clear a newer lifecycle. Failed requests log only operation, error category, and HTTP status; end cleanup is bounded at 15 seconds, with the backend's three-minute expiry as fallback.
- Social refreshes accepted-connection presence and authorized live invitations on selection/foreground return and every 30 seconds while resumed. It stops polling when backgrounded or navigated away. Feed selection and pull-to-refresh also refresh both sources.
- Automatic refresh retains at least the loaded connection count (or all remaining rows when the list shrinks), serializes with connection pagination, and updates only connection fields so loaded feed pages survive. Failed refreshes retain the last loaded data. No live invitation grants access beyond the existing authenticated follower endpoint.
- The conditional 70 dp avatar rail uses the existing 40 dp avatar, first name, and 14 dp spacing. Active invited sessions show a voice badge and open Live Cheer; other recording connections show a dot and open their profile. Empty presence hides the section.
- Analytics: `social_active_now_exposed` retains count buckets; `social_active_now_selected` uses `cheer`/`profile` and `entry_source=active_now`. Follower entry records `entry_source=social_active_now` and the current/average pace selection, without identities, session IDs, audio, or live metrics.
- Verification: debug app assembly and release Kotlin compilation; no test suite. Source review covered active/paused/finished/discarded/recovered sessions, cancellation ordering, unavailable/offline responses, empty presence, authorized/unauthorized routing, loaded-page retention, and foreground lifecycle. Cross-account, cross-device live presence, voice sending/playback, accessibility output, and side-by-side visual equality remain unverified on device.
