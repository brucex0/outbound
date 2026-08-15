# Social

## Current Social implementation

Social is the production social surface. `GET /v1/social/home` returns only the signed-in runner's accepted connections, joined groups, compatible upcoming group runs, and connection-visible posts. The previous `/v1/social/together` path remains as a temporary backend alias. The client caches the last successful response for a useful offline state. Invitations, Cheers, comments, group joins, and activity sharing are authenticated mutations. Compatibility explanations are share-safe and never expose private plan inputs or health reasons. The database and some internal DTOs retain `Club` names while the product consistently says `Group`.

The production Social header has a persistent Connections entry. Connections supports authenticated listing, name/username search, requests, acceptance, decline/cancel, and removal. Pending incoming requests also appear as contextual shortcuts on Social home. Referrals remain invitation links and do not silently create a connection.

The header keeps only two compact actions: a community menu for Connections and Groups, plus Notifications. Connections uses an always-visible inline search field rather than relying on the navigation bar's collapsible search presentation.

The support loop is API-backed: each newly synced activity automatically creates one Connections-visible post. Later syncs do not duplicate it, and deleting the post keeps that activity out of the feed. A runner can Cheer or remove a Cheer, open the full comment sheet, and add a comment. Post reads and mutations verify connection visibility on the server. Private reflections and coaching context are never included in Social responses.

Safety is server-owned. Runners can report posts or comments, block an author, review their block list, and unblock. A block removes any connection and is enforced in people search, connection creation, feed queries, and post mutations. Authors can delete their posts; comment authors and post owners can delete comments.

The in-app notification inbox covers connection requests and acceptance, Cheers, comments, targeted group-run invitations, and invitation acceptance. Opening the inbox marks current notifications read.

Groups are the user-facing product term. Discovery, membership, and group runs use `Group` in UI copy; the existing Prisma `Club` and `ClubMembership` names remain internal. Runners can discover and join/leave Groups, open a group-run detail, RSVP, invite a specific accepted connection, share a link, and accept targeted invitations from Notifications.

Together referral and group-run invitations are shared as a single plain-text message containing the canonical URL. Do not add a separate `URL` activity item: some messaging apps serialize that secondary clipboard representation as an extensionless Apple binary property-list attachment.

Open this when changing the Social tab, social graph concepts, feed cards, clubs, relays, challenges, or rivalry loops.

## Product Direction

Social is the app's network-effect surface. It should make runs feel shared, timely, and worth returning to even before a user starts recording.

Core loops:

- `Squad`: friends' runs, live relays, cheers, comments, and route prompts.
- `Groups`: opt-in communities around time, place, identity, and recurring runs.
- `Rivals`: lightweight weekly competition and segment ownership.
- `Activity visibility`: newly synced activities appear for Connections by default, with post deletion as the opt-out.

## Current iOS Shape

- `Domains/Social/SocialHomeView.swift` owns the production Social home and Connections UI.
- `Domains/Social/TogetherStore.swift` and `TogetherContracts.swift` still retain their earlier internal names while owning API-backed Social home, connection, invitation, referral, and Cheer state; rename these after external behavior stabilizes rather than maintaining a second store.
- `Features/Simplified/SimplifiedAppShell.swift` owns the `Social · Today · Me` tab shell and routes Today's social invitation into Social.

- `Social/ActivityFeedView.swift` owns the local social hub UI.
- `Social/SocialModels.swift`, `Social/SocialSeed.swift`, `Social/SocialStore.swift`, and `Social/SocialRecognitionStore.swift` own Social-only models, seed data, interaction state, and Social-only recognition awards.
- The Social module is behind the `OUTBOUND_ENABLE_SOCIAL` Swift compilation condition.
- The legacy prototype flag should remain unset; production Social is independent of it.
- The current implementation is local/seeded UI state. It does not call a backend yet.
- Squad feed cards use route previews, cheers, local comments, route prompts, report, and block controls.
- Clubs support local join/leave state. Challenges support local join state and progress cards.
- Relays can be locally composed from route, time window, and audience choices, then appear in Squad.
- Rivals show a weekly leaderboard and a local edge-claim action.
- Social assistant copy and Social-only recognition state are also gated behind `OUTBOUND_ENABLE_SOCIAL`; no-social build artifacts should not contain Social/Squad/Rival/Relay/Cheer strings.

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
Until that job runs, read-only Social home, block-list, and notification-list calls degrade to empty safety data when Prisma reports that the new tables do not exist. Core mutations such as connection requests and acceptance still complete when only their optional notification write is unavailable; mutations that directly own records in the new tables still require the schema.

## Deferred

- Push notification delivery; the inbox is complete without APNs.
- Group creation and administration; launch Groups are managed/seeded.
- Public following, public feed ranking, direct messages, circles, rivals, challenges, and relays.
- Automated moderation classification and an operator review console; reports are persisted but still require response ownership.
