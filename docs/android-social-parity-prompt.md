# Android Social Feature-Parity Implementation Prompt

Status: current pre-consolidation parity reference. Do not implement Circle as a separate Android destination after the unified Group contract in `docs/run-groups.md` enters implementation; port the listed private-motivation behavior into Groups instead.

Copy the prompt below into the Android implementation task. It is intentionally detailed: feature parity means equivalent behavior, state, privacy, accessibility, and cross-platform interoperability, not a literal SwiftUI translation.

---

Implement full Android feature parity with Plainstride's production iOS Social experience.

## Working rules

- Work in `/Users/brucexia/dev/outbound` and obey `AGENTS.md`.
- Before editing, read `docs/INDEX.md`, then `docs/android-port.md`, `docs/social.md`, `docs/your-circle.md`, `docs/notifications.md`, `docs/product-analytics.md`, and `docs/android-build.md`.
- Treat these production iOS files as the behavioral source of truth and read them completely:
  - `ios/Outbound/Outbound/Domains/Social/SocialHomeView.swift`
  - `ios/Outbound/Outbound/Domains/Social/TogetherContracts.swift`
  - `ios/Outbound/Outbound/Domains/Social/TogetherStore.swift`
  - `ios/Outbound/Outbound/Domains/Social/CircleContracts.swift`
  - `ios/Outbound/Outbound/Domains/Social/CircleStore.swift`
  - `ios/Outbound/Outbound/Domains/Social/CircleViews.swift`
  - `ios/Outbound/Outbound/Domains/Social/CreateActivityEventView.swift`
  - `ios/Outbound/Outbound/Domains/Social/ActivityEventLocationPicker.swift`
  - `ios/Outbound/Outbound/Domains/Social/ConnectionQRCodeViews.swift`
  - `ios/Outbound/Outbound/Domains/Social/SocialProfileLink.swift`
  - `ios/Outbound/Outbound/Domains/Social/WorkoutPresenceController.swift`
  - the Social/Circle methods in `ios/Outbound/Outbound/Core/APIClient.swift`
  - Social notification routing in `ios/Outbound/Outbound/Core/PushNotificationCoordinator.swift` and `ios/Outbound/Outbound/App/AppDelegate.swift`
  - Social/Circle events and property allowlists in `ios/Outbound/Outbound/Core/Analytics/ProductAnalyticsEvent.swift`
  - event recording/save integration wherever `recordingActivityEventID`, `prepareToRecord`, `consumeRecordingActivityEventID`, `linkActivity`, `markActivityEventWithoutRecording`, or Circle contribution receipts are used.
- Audit the existing Android implementation before changing it, especially `android/feature/social`, app navigation/deep links, notification code, recording/save flows, recognition, activity detail, maps, design system, localization, and analytics. Preserve good foundations but replace placeholder or compressed dialog UX where it cannot express the iOS behavior.
- Do not use `ios/Outbound/Outbound/Social/ActivityFeedView.swift`, `SocialModels.swift`, `SocialSeed.swift`, or `SocialStore.swift` as the contract. Those are the obsolete `OUTBOUND_ENABLE_SOCIAL` seeded prototype. Do not enable or port legacy Squad/Rivals/Relay/challenge behavior.
- Build native Kotlin/Jetpack Compose behavior; do not translate SwiftUI line by line. Reuse the existing backend and stable IDs. Product copy must say **Groups**, even where backend DTO/database names still say `Club`.
- Do not change backend contracts merely to fit the current Android DTOs. First compare Android DTOs with the canonical server response validators and iOS DTOs, then make Android decode the real contract, including nullable and backward-compatible response fields.
- All new visible and accessibility strings must be naturally localized in English, Spanish, and Simplified Chinese. Use locale-aware dates, times, numbers, plurals, units, and relative labels.
- Add/update analytics in the same change. Never log names, usernames, IDs, search text, comments, captions, Circle names, coordinates, exact timestamps, routes, health/plan causes, or other free text.
- Do not run the test suite unless explicitly asked. Run the appropriate Android build-only compile check and lint/static verification described in `docs/android-build.md`. Commit the finished Android work with a `[Droid]` title. Keep unrelated changes out of the commit.

## Product boundary and information safety

- Social home may return only the signed-in runner's accepted connections, joined Groups, compatible upcoming activity events, past events, and connection-visible posts.
- Keep readiness, injury, cycle/medical context, private plan inputs and reasons, reflections, coaching prompts/responses/inferences, and client snapshots out of Social.
- Feed/activity detail may expose only the server's share-safe activity summary, actual activity start time, statistics, approved recognition, photo, and privacy-trimmed route data.
- Circles are invitation-only. Member-authorized Circle detail may include the explicitly permitted current-week workout summary fields, but not route geometry/coordinates, health context, private planning context, reflections, or internal source activity IDs.
- Blocks override discovery, connection creation, feed access/mutations, Circle access, and invitations. Never infer attendance from GPS. Never auto-accept a connection from a referral or QR scan.
- Use opaque stable user, relationship, post, event, invitation, Circle, notification, and cursor IDs. Usernames are display/discovery fields, not relationship keys.

## Architecture and state

- Keep `feature:social` as the Social UI/domain boundary and use existing core network, account-scoped Room cache, auth token provider, analytics, maps, notifications, recognition, and design-system modules.
- Split the current monolithic `SocialScreen.kt` into maintainable screens/components and a testable state holder/repository layer. Dialogs are appropriate only for short confirmations or preset selection; profiles, Connections, event detail, Circle detail/management, comments, search results, Groups, blocks, QR, and creation flows need proper destinations/sheets equivalent to iOS.
- Model loading, refreshing, paginating, empty, cached/stale, mutation-pending, success-toast, and error-toast states independently. Do not blank useful cached content during background refresh.
- Social home, the accumulated feed, connection pages, Circle summaries, recognitions, and other intentionally cached authorized state must be account-scoped and locale-scoped where rendered server copy can vary. Clear memory and persisted data on logout/account switch; never display one account's meetup coordinates or Social data to another.
- Guard async results by active account/generation so a late response cannot repopulate state after account switch.
- Preserve cached content on refresh failure and show a temporary localized toast. Do not insert raw HTTP errors or permanent status rows into page layout.
- Mutations must disable only conflicting controls, be idempotent where the server supports it, reconcile with canonical responses, and refresh the smallest necessary surfaces. Prevent duplicate comments, invitations, Cheers, posts, page items, and event links.
- The Social tab must remain useful offline. Cached state is readable; authoritative mutations fail honestly with transient feedback and must not fabricate success.

## Social home hierarchy and navigation

Match the production hierarchy and visibility rules:

1. Optional active **Cheer someone on** live-session rows.
2. A contextual incoming connection-request shortcut when present.
3. Persistent Connections section:
   - show a footprint-matched loading placeholder until the first snapshot completes so lower sections do not jump;
   - if accepted connections exist, show compact previews ordered by active workout first, then first name;
   - if the successfully loaded result has no accepted connections, show the Better Together growth card with Find people and Invite actions;
   - never flash the growth card for an unknown/unloaded state.
4. **Your Circle**, including invitation cards, empty creation card, or Circle rows with the primary first.
5. A fresh `Guide noticed this` Social-recognition highlight when eligible.
6. **Upcoming**, always visible, with explicit empty state, Discover action, and Plan activity action.
7. **Past activities**, always visible with explicit empty state and shared event results.
8. Joined **Groups**, with discovery available from the community menu.
9. **Recent activity** feed, with empty state and cursor pagination.

The top actions include global conditions, a community menu containing Groups and Explore routes, and a notification bell. Keep Connections out of that menu because it owns a persistent home section. Badge the bell for actionable incoming connection requests and activity-event invitations until handled, not merely for every unread informational notification.

Support pull-to-refresh of home, Connections, Circles, Circle invitations, notifications, and live-Cheer sessions concurrently where safe. Refresh Social after a local activity gains a canonical server activity ID so the automatic post appears. Route notification/deep-link destinations to Connections, post/shared activity detail, event/invitation, Circle, Group, and live Cheer without losing the intended destination through authentication or process recreation.

## Connections, discovery, profiles, referral, and QR

- Connections is a full screen with an always-visible inline search field and distinct Requests, Connections, Sent, and Blocked states/sections.
- Load relationships 20 at a time with the stable opaque cursor. Pull-to-refresh resets to the newest page. Event/Circle invitation pickers must exhaust remaining pages so eligible accepted connections are never silently omitted.
- Use compact circular icon actions with at least 48dp Android touch targets and explicit TalkBack labels for accept, decline/cancel, connect, invite, unblock, and send. Keep text for navigation or stateful actions needing explanation.
- Search accepts one Unicode character. Apply NFKC normalization and trim presentation whitespace; debounce changes, cancel stale jobs, and also submit IME Search immediately. Do not impose a Latin minimum or transliterate identities.
- Show debounced autocomplete in a floating panel immediately below the field. IME submission opens a dedicated Search people screen. Do not merge matches into relationship lists.
- Preserve server ranking/match behavior. Analytics contain only coarse query-length bucket, input-script category, result count bucket, match mode, source, and success/failure—not the query.
- Profiles show avatar, display name, username, relationship-aware actions, and only shareable recognitions. Opening from any surface records only the entry source. Removal requires confirmation.
- Add a Blocked accounts screen with refresh and unblock. Blocking a feed author immediately removes inaccessible data from visible state.
- The add menu includes Scan QR code, Show my QR code, and Invite by link.
- Generate/share only canonical `https://plainstride.ai/connect/:code` URLs based on the opaque connection-link code. The QR must not contain an account ID or username.
- Implement QR scanning with CameraX/ML Kit or the established Android scanner stack. Accept only the canonical HTTPS host/path, stop scanning after a valid code, and open the read-only Social profile preview.
- Cover camera first use, denial, permanent denial with Settings recovery, unavailable hardware, invalid code, self-scan, existing/pending/accepted relationships, block conflict, offline/retry, and duplicate scan idempotency.
- A QR scan or Universal/App Link preview never mutates the relationship. Only an explicit Connect action creates a normal pending request; it never auto-accepts. Preserve a pending Universal/App Link through authentication and clear it only after a terminal/idempotent preview result.
- Share a single plain-text invitation containing the canonical URL. Do not attach a second URL/stream item.

## Active-workout presence and live Cheer entry

- Integrate recording state with `PUT /v1/social/workout-presence` and `DELETE /v1/social/workout-presence/:clientSessionId`.
- Start presence when recording begins, retain it while active or paused, heartbeat once per minute, and explicitly end it on finish/discard/terminal cleanup. Server expiry remains the fallback after three missed minutes.
- Connections see only `isInActiveWorkout`; never expose location, metrics, goal, time, or a recording/session identifier.
- Surface authorized live-Cheer invitations/sessions at the top of Social and route notification opens to the live follower experience with the correct entry-source analytics.

## Feed, comments, profile, safety, and shared activity detail

- Load 12 newest visible posts from the runner and accepted connections. Cursor order is activity start time plus post ID. Append automatically near the list end, de-duplicate by ID, keep accumulated pages in cache, and reset on pull-to-refresh.
- Display dates using the activity's actual start time; use post creation time only for legacy cached responses missing activity time.
- Cards are map-first: privacy-safe light route preview; overlaid distance/time/pace strip; optional recognition pill on the map; caption below; Cheer and comment icon/count actions; 44pt-equivalent/48dp targets; accessible selected/unselected Cheer semantics.
- Absence or invalidity of route geometry must render a polished non-map fallback. Decode the canonical route/geometry shape safely; do not assume the current Android `JsonElement` heuristic is the complete contract.
- The overflow menu contains only delete for the author or report/block safety actions for others. No repost.
- Cheer is a toggle using PUT/DELETE semantics, with immediate consistent UI, mutation guarding, canonical count reconciliation, failure rollback/toast, and recognition refresh as needed.
- Comments are a full sheet/screen, not a cramped alert: list comments, show author/date, cap new bodies at 500 characters after trimming, submit with keyboard/action handling, allow deletion by comment author or post owner, allow reporting comments, preserve loaded comments by post, and show transient retry feedback.
- Reporting supports the canonical reasons and sends `targetType`, target ID, and reason. Post and comment report paths must both exist. Blocking requires clear destructive confirmation and removes the connection as enforced by the backend.
- Authors can delete their posts; soft-deleted posts must not be recreated by client repair logic.
- Opening a post uses the same layered map-and-sheet activity-detail model as Me: shared map/stats/route analysis/share behavior, tappable author profile and caption, fixed Cheer/comments actions, with all owner-only editing and private/unavailable metadata removed.
- Reuse the app-wide avatar cache/request coalescing and recognition cache rather than loading duplicates per row.

## Groups

- Show joined Groups on Social and a full discoverable Groups screen.
- Support refresh, empty/loading/error states, join/leave, and membership reconciliation through the existing APIs.
- Open compatible Group activity events and retain source labeling. Product UI always says Group, never Club.

## Activity events: create, invite, discover, join, record, and results

Implement the complete durable event loop: `Plan -> Invite -> Discover -> Review -> Joined -> Record -> Reconcile`.

- Creation is a two-stage flow: Plan activity, then Invite friends.
- Capture title/name, start date/time, optional duration (default 60 minutes), optional meetup label plus exact latitude/longitude, optional pace/note, and optional Circle source ID. The MVP sends running/fixed/hybrid semantics expected by the backend.
- Every event is explicitly hybrid: display **Meet up or join from anywhere** throughout creation, cards, detail, and recording entry. Meetup is optional.
- Android location selection must provide Google Places/autocomplete if already configured or an equivalent approved Google/Maps implementation, plus Choose on map. Save the resolved label (maximum 120 characters) and exact selected coordinates; do not infer coordinates from arbitrary typed text. Handle permission denial without making location mandatory. Emit only `activity_event_location_selected` with coarse source type (`search`, `map`, etc.), never place text or coordinates.
- Creation automatically joins the owner. The second stage supports multi-select accepted connections, preselection from Circle detail, review/edit, disabled states for already invited/going users, batch invitation, partial results, retry, and no duplicate selection.
- Upcoming includes connection-visible, directly invited, joined, and joined-Group compatible events with share-safe source labels. Discover has its own screen and refresh.
- Detail displays organizer/source, exact schedule and duration, scheduled end, results deadline, hybrid explanation, optional meetup map/directions affordance, optional note/pace, attendee previews/list, each participant's explicit in-person/virtual intent, owner/participant roles, pending targeted invitations for the organizer, and lifecycle-aware actions.
- Joining or accepting an invitation requires choosing `in_person` or `virtual`. Store attendance intent independently of recording and never infer it from location.
- Owner: no redundant RSVP or Leave; can invite, cancel a pending targeted invitation (which removes its notification), share canonical event URL, and start the event. Participant: can join/leave while allowed, select/change attendance as supported, and start a joined event.
- Shared links use canonical `/invite/activity/:token`, survive authentication, and join idempotently.
- Starting uses an event-specific session intent and event title, not Quick Run/planned-workout intent. Persist event ID in the active-session journal so process death cannot sever the association.
- Saved activity stores the event ID. After sync obtains the canonical activity ID, call link-activity idempotently, refresh results/Social, and display the shared result/post without app restart.
- Finishing then discarding an event recording calls no-recording and resolves participation without creating a personal activity. Never synthesize a history activity for a non-recorder.
- Lifecycle is `scheduled -> active -> reconciling -> completed`, with terminal `cancelled`. Only scheduled/active appear in Upcoming; reconciling/completed appear in Past activities.
- Results use participation-neutral language. Show each person's stats only where relationship visibility permits, and support unresolved/no-recording states. Personal history gets a subtle Shared activity marker linking back to the event.

## Your Circle

- Preserve all rules in `docs/your-circle.md`: multiple Circles, backend-delivered member limit, owner plus explicit invitations, first eligible active Circle becoming primary, active/awaiting-members/archived lifecycle, account-owned primary selection, and no competition/rank/guilt framing.
- Social placement is directly below Connections. Pending invitations come first. Show the creation card only after Connections loaded successfully and at least one accepted connection exists. With multiple Circles, order primary first.
- Creation is one scrollable screen: inspirational card; accepted-connection multi-select; optional name; capacity-aware disabling without advertising a fixed maximum; sticky Create action. Load all connection pages. Create using local timezone/reset weekday.
- After creation, show the dedicated success/education state with invited people, supported activity types, Cheers/workout visibility explanation, **Choose a weekly focus** primary action, **Open Circle** secondary action, and clear wording that a numeric goal is optional.
- Circle detail must be a real screen containing relationship statement, weekly interval/progress, member rows, current-user contribution, each member's recent authorized workout context, preset Cheer action, recent Circle moments, Plan an activity, history, weekly focus, and management.
- Weekly focus modes: personal targets, shared target, and no target. Support sensible presets plus bounded custom values, `Skip this week` distinct from zero, and changes applying `now` or `next_week`. Only a member edits their own personal commitment; only the owner controls shared target/default focus.
- Contributions include recorded, imported, and manual canonical activities, selected by actual activity start time, once per Circle/week. Android must consume server reconciliation; do not calculate authoritative contribution locally.
- Cheers use localized presets such as encouragement, celebration, and support. No free text, points, rank, or spam-producing duplicate behavior. Support removing a Cheer.
- Plan an activity reuses the normal event creation flow with Circle members preselected but editable and preserves `sourceCircleId`.
- Management supports rename; invite/cancel invitation; personal target/skip; primary selection; notification mute; reset weekday/timezone and now/next-week application; owner remove member; ownership transfer; archive/reactivate; and member leave. Enforce owner restrictions and use confirmations for destructive actions.
- Show transient success/error toasts. Cache only authorized summaries/details by account and revoke inaccessible state immediately after leave/remove/block.
- Consume confirmed post-save Circle contribution receipts, show a compact non-blocking contribution result, refresh Circle state, and present one Reduce-Motion-aware weekly completion celebration exactly once per member using the server presentation endpoint. If offline, save normally and wait for confirmed reconciliation rather than claiming contribution.

## Notifications and links

- Implement the in-app inbox from the Social notifications API, independently of Android system-notification history.
- Cover connection request/accepted, post Cheer, comment, targeted event invitation/acceptance, Circle invitation/acceptance/Cheer/completion/ownership, Group/event, and live-Cheer types supported by the backend.
- Rows show localized type-specific content and route to actionable context: Connections, shared post/activity/comments, event or invitation attendance choice, Circle, Group, or live Cheer.
- Opening the inbox records `social_inbox_opened` and marks current notifications read. Read state alone does not clear actionable invitation badges; handling the request/invitation does.
- Register/unregister FCM devices with the existing backend, honor Android 13+ notification permission and app preference, configure channels, and route cold/warm notification taps through authentication to the exact destination. Track push opens only with normalized notification type and destination.

## Recognition

- Use server-owned awards and account-scoped offline presentation. Support Good Teammate, Relay Player, and Photo Finish as returned by the backend; do not revive manual Rival Edge.
- Show a fresh Social award in the lightweight `Guide noticed this` card for three days, a compact applicable milestone pill on feed maps, and only the shareable subset on another runner's profile.
- Refresh/reconcile awards after relevant Cheer, Group/event join, and photo-share outcomes. Sharing an award must use Android's plain-text share sheet without exposing private data.

## Analytics

Bring Android's typed allowlist to parity with the iOS event names and allowed properties. At minimum cover:

- `feature_exposed`, `activity_feed_loaded`, `paginated_list_page_loaded`, `connections_opened`, `connections_search_completed`, `social_profile_opened`, `social_inbox_opened`, `push_notification_opened`, `connection_qr_code_request_result`, `social_operation_failed`;
- `group_run_create_attempted`, `group_run_created`, `group_run_join_attempted`, `group_run_joined`, `group_run_invite_shared`, and `activity_event_location_selected`;
- every Circle event in `ProductAnalyticsEvent.swift`: section exposed; creation start/success/failure; invitation send/accept/decline/cancel; activation; focus/target changes; progress open; Cheer send/remove; plan-activity start/complete; contribution reconciliation; weekly completion; primary change; notification change; rename/calendar/ownership/member/leave/archive/reactivate; normalized operation failure.

Use exactly the existing allowlisted property keys and coarse bucket helpers. Include Android's platform value where the shared contract expects it. Analytics failure must never break product behavior.

## Accessibility, adaptive UI, and polish

- Use Material/Plainstride semantic colors and all supported themes; verify light/dark and high contrast.
- Support font scaling without clipped cards/actions, TalkBack traversal and state announcements, switch access, keyboard/IME actions, and minimum 48dp touch targets.
- Give icon-only actions meaningful localized content descriptions and selected/state semantics. Maps need nonvisual route/stat summaries; decorative icons must be hidden from accessibility.
- Respect system Reduce Motion for Circle completion and other animation. Preserve scroll position and destination state across recomposition/configuration; restore critical pending event/QR/deep-link state across process recreation.
- Use skeletons/placeholders only to preserve layout while initial data is unknown. Use explicit polished empty states after successful loads.

## Verification and definition of done

- Produce a short parity audit mapping every production iOS screen/action/state above to its Android implementation and call out any deliberate platform substitution.
- Verify real DTO shapes against backend validators/routes and exercise iOS-created data on Android and Android-created data on iOS.
- Build-only compile all affected Android modules/variants and run lint/static checks allowed by `AGENTS.md`; do not run the test suite unless asked.
- Manually smoke-check at least: cached/offline launch; account switch; no/one/many connections; incoming/sent requests; one-character Chinese search and IME submission; relationship pagination; QR success/denial/invalid/self/duplicate; empty and paginated feed; Cheer rollback; comment create/delete/report; post delete/report/block/unblock; Group join/leave; event create/location/invite/attendance/start/save-link/discard-no-recording/results; Circle create/invite/focus/Cheer/plan/manage/complete; inbox read/action badge behavior; cold/warm deep links; EN/ES/zh-CN; TalkBack/font scale; and Android/iOS interaction.
- Confirm no Social response or analytics payload exposes private training/health causes, free text, IDs, coordinates, routes, or exact timestamps outside the explicit share-safe product contract.
- Update focused documentation if behavior, setup, architecture, contracts, or verification commands change.
- Commit only the completed Android/documentation changes with a focused `[Droid]` commit after verification succeeds.

When finished, report: files changed, parity behaviors completed, platform substitutions, verification commands/results, commit hash, and any genuine remaining blocker. Do not claim parity if an item above is still represented only by a placeholder dialog, hard-coded sample, no-op callback, or unverified DTO assumption.
