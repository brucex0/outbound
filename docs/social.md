# Social

## Current Social implementation

This section describes the shipped shape. `docs/run-groups.md` defines the recommended target that consolidates Circle and Groups into one Groups destination and one model.

Social is the production social surface. `GET /v1/social/home` returns only the signed-in runner's accepted connections, joined groups, compatible upcoming group runs, and connection-visible posts. The previous `/v1/social/together` path remains as a temporary backend alias. The client caches the last successful response for a useful offline state. Invitations, Cheers, comments, group joins, and activity sharing are authenticated mutations. Compatibility explanations are share-safe and never expose private plan inputs or health reasons. The database and some internal DTOs retain `Club` names while the product consistently says `Group`.

Social uses one sticky compact feature row with five destinations: `Feed`, `People`, `Circle`, `Groups`, and `Routes`. A runner with accepted connections initially lands on Feed; a runner without accepted connections initially lands on People. The choice is made only once per Social presentation, so a connection refresh never switches tabs underneath the runner. Each destination retains its production store and navigation destinations rather than nesting another navigation stack.

People embeds the production Connections experience: authenticated listing, search, requests, acceptance, decline/cancel, removal, QR, referral, and block management. With no accepted connections, discovery becomes the primary content through labeled Find people, Invite a friend, and Scan QR actions. Search accepts a single Unicode character, normalizes compatibility forms before lookup, and submits committed keyboard input as well as debounced changes, so Chinese names work without a Latin-centric minimum length. One- and two-character queries remain literal; longer queries use indexed trigram matching so minor typos can still find a display name or username. Exact, prefix, and substring matches rank ahead of fuzzy results. Search remains within the entered script and does not transliterate identities between scripts. Its server list uses a stable opaque cursor ordered by relationship update time and ID, and the screen loads 20 relationships at a time. Pull-to-refresh resets the list to its newest page; event invitation pickers exhaust the remaining pages so eligible friends are not silently omitted. Referrals remain invitation links and do not silently create a connection.

Feed begins with conditional compact context only: Active now when an accepted connection is recording, then up to three prioritized Upcoming cards, then Activity Feed. Invitations needing action come first, followed by joined or relevant activities inside 72 hours and then later activities. Upcoming disappears completely when empty, while See all owns the complete upcoming and past-event history. Active presence remains share-safe: the connection response exposes only a boolean—never workout metrics, location, goal, timestamps, or session IDs—and only an existing authorized live-share session opens live Cheer; otherwise the avatar opens the connection profile. Permanent People, Circle, milestone, past-event, and joined-Group sections no longer sit above the feed.

Usernames are editable from Me and use 3–30 lowercase letters, numbers, underscores, or hyphens. The backend owns normalization, uniqueness, and reserved-name enforcement. A user may change their username once every 30 days, and the previous username remains reserved to that account for the same period to reduce impersonation risk. Relationships, posts, invitations, QR connection links, and routes continue to use stable user IDs rather than usernames. Username-change analytics record only the bounded fact that a change occurred, never either handle.

The signed-in runner's Me and Profile cards expose an owner-only QR action. That shortcut and Me's My invite entry open the same QR-first screen, whose permanent eight-character lowercase-alphanumeric code also supports copying and remote sharing. Connections' add menu still provides Scan QR code, Show my QR code, and Invite by link. The canonical QR and invitation URL is `https://plainstride.ai/invite/r/:code`; scanners and App Links also accept the compatible `/connect/:code` form. Opening a recognized link claims the referral when the signed-in member is eligible, opens the owner's Social profile, and lets the viewer explicitly Connect; opening alone never sends a connection request. Scanning from the explicit in-app connection scanner sends a normal pending request and also claims an eligible referral. Denied camera access provides a Settings recovery action, while unsupported devices receive an explicit unavailable state. The authenticated read-only lookup returns only the owner's existing Social identity and the viewer's relationship state; blocked and invalid links remain indistinguishable as not found. Connections never auto-accept. Self links, existing pending requests, accepted connections, blocks, invalid codes, and retryable network failures remain idempotent without exposing account IDs or personal codes in analytics.

People keeps discovery in its always-visible inline search field. Debounced matches appear in a floating autocomplete panel directly below the field instead of being appended to the relationship list. Submitting from the keyboard opens a dedicated Search people screen with full results and relationship actions; autocomplete and submitted-result states remain visually separate from Requests, Connections, Sent, and Blocked. The standalone Connections destination retains its QR/referral add menu for entry points outside the Social tab.

Background refresh failures leave cached Social content in place and use a transient localized toast rather than inserting raw HTTP status text into the page layout.

Circle is a dedicated destination. It shows pending invitations, meaningful creation content when empty, and compact Circle navigation with the account-owned primary first. Circle detail owns the optional Weekly Focus, member progress, preset private Cheers, existing activity-event planning flow, recent Circle moments, history, and management. Today consumes only the primary eligible Circle and keeps imminent joined activity events ahead of it in the existing one-opportunity slot. The full product and privacy rules remain canonical in `docs/your-circle.md`.

Notifications remain a dedicated top-toolbar action. A fixed Create/Add menu has stable meaning on every Social destination and routes to the supported Plan a run, Add person, Create Circle, and route-import flows. Groups and Routes are explicit tabs rather than overflow-menu destinations. Groups shows joined Groups before discovery and intentionally does not offer arbitrary Group creation. Routes reuses the community library and supported saved, bookmarked, import, publish, and activity-owned route flows.

The feature-row badges summarize trustworthy action/content state without replacing the chronological notification inbox. People shows unresolved incoming connection requests; Circle shows unresolved Circle invitations; Feed uses an account-scoped latest-viewed-post watermark and clears its dot only after the runner explicitly opens or refreshes Feed and the refresh succeeds. Opening the bell does not resolve those underlying states. Groups and Routes intentionally remain unbadged until their contracts expose reliable personally relevant update signals. Numeric badges cap visually at `9+`; badge analytics record only bounded destination, kind, source, and count buckets.

Compact Social rows use circular icon actions with 44-point tap targets for recognizable commands such as accept, decline, connect, invite, unblock, and send. Text remains on primary navigation, RSVP, membership, and other actions whose state or destination needs a label.

Feed activity cards are map-first: a light route preview carries an overlaid distance/time/pace strip, followed by optional caption and icon-plus-count Cheer and comment actions. Feed, profile, notification, and shared-detail dates use the activity's actual start time, including for workouts imported after they occurred; post creation time remains only a fallback for cached legacy responses. When one of the runner's account-backed recognitions belongs to their activity, its compact milestone pill appears directly on the map. The 44-point overflow target contains only delete or safety actions; repost is not part of the feed menu. Social responses select only share-safe activity summary, timing, and route fields rather than returning private reflection, guidance, or client snapshot data.

The home activity feed uses a stable opaque cursor ordered by activity start time and post ID, matching the timestamp displayed on each card. This keeps workouts imported after they occurred in their chronological position and makes page boundaries visually monotonic. It loads 12 newest visible posts across the runner and accepted connections, then automatically appends subsequent pages as the runner reaches the end. Pull-to-refresh resets to the newest page, while the cached accumulated feed remains useful offline.

Opening a feed activity reuses the same layered map-and-sheet detail shell as Me, following Strava's one-detail-screen model. Social keeps the common map, stats (including stored elevation gain and calorie total), route analysis, and Share action; adds a tappable author profile card and caption in the sheet; pins Cheer and comments at the bottom; and does not expose owner-only editing or unavailable private activity metadata. Calories come only from the activity owner's stored summary and are never recalculated using the viewer's private weight. Post payloads include the cheerers' share-safe profiles: the detail shows the first five cheerer avatars followed by the total count, and tapping the count opens the full list, where every row opens that runner's profile.

The production Social tab participates in the account-backed recognition layer. The server awards `Good Teammate` after support on three distinct friends' activity posts in a calendar week, `Relay Player` after joining a Group or activity event, and `Photo Finish` after sharing an activity with a photo. The client caches those awards for immediate/offline presentation, and a fresh Social recognition appears as a lightweight `Guide noticed this` card for three days. `Rival Edge` remains dormant until the deferred Rivals feature has a real backend-owned outcome rather than a manual claim button. Accepted connections can see only the small shareable subset of another runner's milestones on their profile.

The support loop is API-backed: each newly synced activity automatically creates one Connections-visible post. Social home repairs missing posts for older synced activities, while soft-deleted posts preserve the runner's opt-out and are not recreated. Later syncs do not duplicate posts. A runner can Cheer or remove a Cheer, open the full comment sheet, and add a comment. Post reads and mutations verify connection visibility on the server. Private reflections and guidance context are never included in Social responses.

Safety is server-owned. Runners can report posts or comments, block an author, review their block list, and unblock. iOS and Android require confirmation before reporting a post, blocking a person, removing a connection, or deleting a post; the post-deletion prompt alone offers a persistent `Don’t ask again` choice. Post reports use the shared harassment, hate speech, spam, sexual content, violence, privacy, and other reason set. A block removes any connection and is enforced in people search, connection creation, feed queries, and post mutations. Authors can delete their posts; comment authors and post owners can delete comments.

The in-app notification inbox covers connection requests and acceptance, Cheers, comments, targeted group-run invitations, and invitation acceptance. Notification rows route to their actionable context: connection events open Connections, Cheers and comments open the shared activity card with comment access, and run events open the run or invitation action. Opening the inbox marks current notifications read, while the bell remains badged for actionable incoming connection requests and run invitations until they are handled.

Groups are the user-facing product term. Discovery, membership, and group runs use `Group` in UI copy; the existing Prisma `Club` and `ClubMembership` names remain internal. Runners can discover and join/leave Groups, open a group-run detail, RSVP, invite a specific accepted connection, share a link, and accept targeted invitations from Notifications.

Together referral and group-run invitations are shared as a single plain-text message containing the canonical URL. Do not add a separate `URL` activity item: some messaging apps serialize that secondary clipboard representation as an extensionless Apple binary property-list attachment.

Open this when changing the Social tab, social graph concepts, feed cards, clubs, relays, challenges, or rivalry loops.

The end-to-end event flow was originally explored in `docs/prototypes/future-activities-e2e.html`. It remains an interaction reference, but the production concept is an activity event because the same object persists before, during, and after its scheduled time.

## Product Direction

Social is the app's network-effect surface. It should make runs feel shared, timely, and worth returning to even before a user starts recording.

Groups are the permanent relationship layer. `docs/run-groups.md` is canonical for the target product, privacy, data, analytics, migration, and implementation contract. It consolidates the current private Circle and community Group shapes while retaining a hard trust-policy boundary for workout visibility.

Core loops:

- `Squad`: friends' runs, live relays, cheers, comments, and route prompts.
- `Groups`: private shared motivation or community coordination around people, time, place, identity, and recurring runs.
- `Rivals`: lightweight weekly competition and segment ownership.
- `Activity visibility`: newly synced activities appear for Connections by default, with post deletion as the opt-out.

## Activity Events

The production activity-event loop follows `docs/prototypes/future-activities-e2e.html`:

`Plan -> Invite -> Discover -> Review -> Joined -> Record -> Reconcile`

- Social's Upcoming add action opens a two-step `Plan a run` / `Invite friends` flow.
- The MVP form stores a name, date/time, optional meetup label, optional exact meetup latitude/longitude, and optional pace/note. The optional meetup field uses native MapKit place autocomplete with a choose-on-map sheet, so the runner can pick a suggestion or center the map on a precise point; the resolved display label is persisted as `locationName` and the exact coordinate pair is persisted on `ActivityEvent` for invited participants to find the meeting spot. No third-party location provider is used.
- Every activity event is hybrid by default: participants may meet at the suggested location or join from anywhere.
- Creation, Upcoming cards, and activity detail label this explicitly as `Meet up or join from anywhere`; the person-and-radio-waves icon reinforces that both in-person and virtual participation are first-class, and meetup location remains optional.
- Creating an activity automatically joins its creator. Eligible connections and invitation recipients join immediately; there is no approval or pending-RSVP state.
- When a connection joins or accepts a targeted invitation, they choose `in_person` or `virtual`; that attendance intent is stored independently from recorded results and never inferred from GPS.
- Connections-visible activities, direct invitations, joined activities, and joined-group activities appear in Upcoming with a share-safe source label.
- A targeted invitation or shared `/invite/activity/:token` Universal Link joins the recipient after authentication.
- Targeted invitations create an in-app notification. APNs delivery is still deferred, so invitees see it in Plainstride's Notifications inbox rather than as an OS push notification.
- The creator's invite picker supports multi-select and marks friends who are already invited or already going so they cannot be selected twice.
- The creator sees pending targeted invitations on the planned activity detail and can delete an invitation before it is accepted; deleting it also removes the invitee's matching notification.
- Today presents one primary next activity. A joined activity event takes precedence over the planned recommendation while Quick Run remains available; after completing a workout, the recommendation remains available as the compact Up next affordance.
- Starting an event uses an event-specific session intent rather than a Quick Run or planned-workout intent. The setup and live session use the event title, while the saved personal activity stores the event ID. Offline sync later links the canonical server activity to that participant idempotently.
- When an event-linked recording finishes syncing, the server resolves that participant and immediately completes the event if every going participant is resolved. Social refreshes from the resulting server activity ID so the shared result and automatic feed post appear without requiring an app restart or manual refresh.
- Reconciliation distinguishes a linked recording from participation without a recording. Finishing and discarding an event recording resolves the participant as finished without saving personal activity data. It never infers physical attendance from GPS.
- Results use participation-neutral language and expose individual stats only where connection visibility permits.
- Event lifecycle is `scheduled -> active -> reconciling -> completed`, with `cancelled` as a terminal alternative. The server derives and persists transitions from `startsAt`, `endsAt`, participant outcomes, and a four-hour reconciliation window after the scheduled end. An event completes sooner when every going participant has resolved an outcome. Only scheduled and active events appear in Upcoming; reconciling and completed events appear under Past activities.
- The owner sees organizer and invitation controls but no redundant personal RSVP or Leave action. Participants see their RSVP and attendance mode. Everyone sees whether each participant plans to meet in person or join from anywhere.
- Every participant's recording remains an ordinary personal `Activity` with its own ID. `ActivityEventParticipant.recordedActivityId` links that record to the shared parent event. Personal history shows a subtle Shared activity marker; Social owns the cross-participant result view. A participant who did not record has no synthetic personal activity row.

The database uses durable `ActivityEvent`, `ActivityEventParticipant`, and `ActivityEventOption` models rather than time-relative or run-specific names. The event has an explicit duration (`startsAt` and `endsAt`). Creation offers an optional duration choice and uses one hour when it is left unset. Activity detail shows the duration, scheduled end, and exact results deadline. The MVP stores `activityType = running`, `activityPolicy = fixed`, and `participationMode = hybrid`; later open activities can set `activityType = null` and allow walking, trail running, cycling, strength, or other activity types without changing invitation, attendance, personal recording, or reconciliation ownership.

This schema replacement is intentionally destructive for pre-release data. Apply it with:

```sh
cd backend
npm run db:generate
npm run db:push -- --accept-data-loss
```

## Current iOS Shape

- `Domains/Social/SocialHomeView.swift` composes the production feature destinations and retains the existing feed, event, notification, Group, and Connections flows; `SocialFeatureTabBar.swift` owns the compact sticky feature selector and restrained badge rendering.
- `Domains/Social/TogetherStore.swift` and `TogetherContracts.swift` still retain their earlier internal names while owning API-backed Social home, connection, invitation, referral, and Cheer state; rename these after external behavior stabilizes rather than maintaining a second store. Together's offline cache is account-scoped and is cleared from memory and storage when authentication changes; exact meetup coordinates are never reused across accounts.
- `Features/Simplified/SimplifiedAppShell.swift` owns the `Social · Today · Me` tab shell and routes Today's social invitation into Social.

- `Social/ActivityFeedView.swift` owns the legacy local social hub UI.
- `Social/SocialModels.swift`, `Social/SocialSeed.swift`, and `Social/SocialStore.swift` retain its seeded models and interaction state behind the `OUTBOUND_ENABLE_SOCIAL` compilation condition.
- `Social/SocialRecognitionStore.swift` is no longer gated with that prototype. Production Social uses it as an account-scoped offline cache and presentation store for server-owned Social awards.
- The legacy prototype flag should remain unset; production Social is independent of it.
- The current implementation is local/seeded UI state. It does not call a backend yet.
- Squad feed cards use route previews, cheers, local comments, route prompts, report, and block controls.
- Clubs support local join/leave state. Challenges support local join state and progress cards.
- Relays can be locally composed from route, time window, and audience choices, then appear in Squad.
- Rivals show a weekly leaderboard and a local edge-claim action.
- Legacy Social assistant and seeded interaction copy remain gated behind `OUTBOUND_ENABLE_SOCIAL`; production recognition copy is always compiled because the production Social tab uses it.

The feature-flagged files above are a legacy prototype, not the production Social implementation. Port useful interaction patterns into `Domains/Social` and then delete the legacy module; do not connect its local store to the backend.

## App Review Readiness

Apple treats apps with user-generated content or social networking services as needing abuse controls. Before enabling `OUTBOUND_ENABLE_SOCIAL` for external beta or release, add:

- Objectionable-material filtering before posts, comments, cheers with text, photos, routes, or profiles are published.
- Report content/user flows with timely developer response ownership.
- Block user controls that affect feed, comments, clubs, relays, rivals, notifications, and search/discovery.
- Published in-app contact information and matching App Store metadata/privacy policy links.
- Privacy controls for activity visibility, route/photo sharing, and live presence.

## Backend Schema Rollout

This slice adds `SocialBlock`, `SocialReport`, `SocialNotification`, `GroupRunRSVP`, and account-owned `RecognitionAward` rows. Apply it to the intended environment before deploying the new API:

```sh
cd backend
npm run db:push -- --accept-data-loss
```

The deployment schema job described in `docs/backend-deploy.md` remains the production path.
Production schema rollout uses the Cloud Run database job documented in `docs/backend-deploy.md`. `Activity.updatedAt` has a database default so existing pre-publish activity rows can be upgraded without blocking the current Social tables. The current production schema was applied successfully on 2026-08-14; Social database errors now surface normally rather than being masked by missing-table fallbacks.

## Deferred

- Push notification delivery; the inbox is complete without APNs.
- Consolidated Group creation and administration are specified in `docs/run-groups.md` but not implemented.
- Public following, public feed ranking, direct messages, rivals, challenges, and relays. The existing Circle implementation is a migration input for the consolidated Group product.
- Automated moderation classification and an operator review console; reports are persisted but still require response ownership.
