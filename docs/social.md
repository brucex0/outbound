# Social

## Current Social implementation

Social is the production social surface. `GET /v1/social/home` returns only the signed-in runner's accepted connections, joined groups, compatible upcoming group runs, and connection-visible posts. The previous `/v1/social/together` path remains as a temporary backend alias. The client caches the last successful response for a useful offline state. Invitations, Cheers, comments, group joins, and activity sharing are authenticated mutations. Compatibility explanations are share-safe and never expose private plan inputs or health reasons. The database and some internal DTOs retain `Club` names while the product consistently says `Group`.

The production Social header has a persistent Connections entry. Connections supports authenticated listing, name/username search, requests, acceptance, decline/cancel, and removal. Pending incoming requests also appear as contextual shortcuts on Social home. Referrals remain invitation links and do not silently create a connection.

The Social home connection-growth card is limited to runners with fewer than three accepted connections. Connections owns the normal add flow through its top-right add menu, which focuses people search or opens referral-link sharing. Upcoming includes a visible Discover entry, also available from the community menu, for browsing compatible activities from connections and joined groups. Upcoming and Recent sections remain visible with explicit empty cards when they have no content.

The header keeps only two compact actions: a community menu for Connections and Groups, plus Notifications. Connections uses an always-visible inline search field rather than relying on the navigation bar's collapsible search presentation.

Compact Social rows use circular icon actions with 44-point tap targets for recognizable commands such as accept, decline, connect, invite, unblock, and send. Text remains on primary navigation, RSVP, membership, and other actions whose state or destination needs a label.

Feed activity cards are map-first: a light route preview carries an overlaid distance/time/pace strip, followed by optional caption and icon-plus-count Cheer and comment actions. Feed, profile, notification, and shared-detail dates use the activity's actual start time, including for workouts imported after they occurred; post creation time remains only a fallback for cached legacy responses. When one of the runner's locally tracked recognitions belongs to their activity, its compact milestone pill appears directly on the map. The 44-point overflow target contains only delete or safety actions; repost is not part of the feed menu. Social responses select only share-safe activity summary, timing, and route fields rather than returning private reflection, guidance, or client snapshot data.

The home activity feed uses a stable opaque cursor ordered by post creation time and ID. It loads 12 newest visible posts across the runner and accepted connections, then automatically appends subsequent pages as the runner reaches the end. Pull-to-refresh resets to the newest page, while the cached accumulated feed remains useful offline.

Opening a feed activity reuses the same layered map-and-sheet detail shell as Me, following Strava's one-detail-screen model. Social keeps the common map, stats, route analysis, and Share action; adds a tappable author profile card and caption in the sheet; pins Cheer and comments at the bottom; and does not expose owner-only editing or unavailable private activity metadata.

The production Social tab also participates in the local recognition layer restored from the earlier prototype. Supporting three distinct activity posts in a calendar week through a Cheer or comment unlocks `Good Teammate`; joining a Group or its run unlocks `Relay Player`; and sharing an activity with a photo unlocks `Photo Finish`. A fresh Social recognition appears as a lightweight `Guide noticed this` card for three days. `Rival Edge` remains dormant until the deferred Rivals feature has a real backend-owned outcome rather than a manual claim button.

The support loop is API-backed: each newly synced activity automatically creates one Connections-visible post. Social home repairs missing posts for older synced activities, while soft-deleted posts preserve the runner's opt-out and are not recreated. Later syncs do not duplicate posts. A runner can Cheer or remove a Cheer, open the full comment sheet, and add a comment. Post reads and mutations verify connection visibility on the server. Private reflections and guidance context are never included in Social responses.

Safety is server-owned. Runners can report posts or comments, block an author, review their block list, and unblock. A block removes any connection and is enforced in people search, connection creation, feed queries, and post mutations. Authors can delete their posts; comment authors and post owners can delete comments.

The in-app notification inbox covers connection requests and acceptance, Cheers, comments, targeted group-run invitations, and invitation acceptance. Notification rows route to their actionable context: connection events open Connections, Cheers and comments open the shared activity card with comment access, and run events open the run or invitation action. Opening the inbox marks current notifications read, while the bell remains badged for actionable incoming connection requests and run invitations until they are handled.

Groups are the user-facing product term. Discovery, membership, and group runs use `Group` in UI copy; the existing Prisma `Club` and `ClubMembership` names remain internal. Runners can discover and join/leave Groups, open a group-run detail, RSVP, invite a specific accepted connection, share a link, and accept targeted invitations from Notifications.

Together referral and group-run invitations are shared as a single plain-text message containing the canonical URL. Do not add a separate `URL` activity item: some messaging apps serialize that secondary clipboard representation as an extensionless Apple binary property-list attachment.

Open this when changing the Social tab, social graph concepts, feed cards, clubs, relays, challenges, or rivalry loops.

The end-to-end event flow was originally explored in `docs/prototypes/future-activities-e2e.html`. It remains an interaction reference, but the production concept is an activity event because the same object persists before, during, and after its scheduled time.

## Product Direction

Social is the app's network-effect surface. It should make runs feel shared, timely, and worth returning to even before a user starts recording.

Core loops:

- `Squad`: friends' runs, live relays, cheers, comments, and route prompts.
- `Groups`: opt-in communities around time, place, identity, and recurring runs.
- `Rivals`: lightweight weekly competition and segment ownership.
- `Activity visibility`: newly synced activities appear for Connections by default, with post deletion as the opt-out.

## Activity Events

The production activity-event loop follows `docs/prototypes/future-activities-e2e.html`:

`Plan -> Invite -> Discover -> Review -> Joined -> Record -> Reconcile`

- Social's community menu opens a two-step `Plan a run` / `Invite friends` flow.
- The MVP form stores a name, date/time, optional meetup label, and optional pace/note.
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

- `Domains/Social/SocialHomeView.swift` owns the production Social home and Connections UI.
- `Domains/Social/TogetherStore.swift` and `TogetherContracts.swift` still retain their earlier internal names while owning API-backed Social home, connection, invitation, referral, and Cheer state; rename these after external behavior stabilizes rather than maintaining a second store.
- `Features/Simplified/SimplifiedAppShell.swift` owns the `Social · Today · Me` tab shell and routes Today's social invitation into Social.

- `Social/ActivityFeedView.swift` owns the legacy local social hub UI.
- `Social/SocialModels.swift`, `Social/SocialSeed.swift`, and `Social/SocialStore.swift` retain its seeded models and interaction state behind the `OUTBOUND_ENABLE_SOCIAL` compilation condition.
- `Social/SocialRecognitionStore.swift` is no longer gated with that prototype. Production Social uses it for local Social milestone evaluation and presentation.
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

This slice adds `SocialBlock`, `SocialReport`, `SocialNotification`, and `GroupRunRSVP`. Apply it to the intended environment before deploying the new API:

```sh
cd backend
npm run db:push -- --accept-data-loss
```

The deployment schema job described in `docs/backend-deploy.md` remains the production path.
Production schema rollout uses the Cloud Run database job documented in `docs/backend-deploy.md`. `Activity.updatedAt` has a database default so existing pre-publish activity rows can be upgraded without blocking the current Social tables. The current production schema was applied successfully on 2026-08-14; Social database errors now surface normally rather than being masked by missing-table fallbacks.

## Deferred

- Push notification delivery; the inbox is complete without APNs.
- Group creation and administration; launch Groups are managed/seeded.
- Public following, public feed ranking, direct messages, circles, rivals, challenges, and relays.
- Automated moderation classification and an operator review console; reports are persisted but still require response ownership.
