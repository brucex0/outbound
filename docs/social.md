# Social

## Current Social implementation

Social is the production social surface. `GET /v1/social/home` returns only the signed-in runner's accepted connections, joined groups, compatible upcoming group runs, and connection-visible posts. The previous `/v1/social/together` path remains as a temporary backend alias. The client caches the last successful response for a useful offline state. Invitations, Cheers, comments, group joins, and activity sharing are authenticated mutations. Compatibility explanations are share-safe and never expose private plan inputs or health reasons. The database and some internal DTOs retain `Club` names while the product consistently says `Group`.

The production Social header has a persistent Connections entry. Connections supports authenticated listing, name/username search, requests, acceptance, decline/cancel, and removal. Pending incoming requests also appear as contextual shortcuts on Social home. Referrals remain invitation links and do not silently create a connection.

The support loop is API-backed: a runner can share the latest synced activity with Connections, Cheer or remove a Cheer, open the full comment sheet, and add a comment. Post reads and mutations verify connection visibility on the server. Private reflections and coaching context are not included in activity-share requests.

Together referral and group-run invitations are shared as a single plain-text message containing the canonical URL. Do not add a separate `URL` activity item: some messaging apps serialize that secondary clipboard representation as an extensionless Apple binary property-list attachment.

Open this when changing the Social tab, social graph concepts, feed cards, clubs, relays, challenges, or rivalry loops.

## Product Direction

Social is the app's network-effect surface. It should make runs feel shared, timely, and worth returning to even before a user starts recording.

Core loops:

- `Squad`: friends' runs, live relays, cheers, comments, and route prompts.
- `Clubs`: opt-in groups around time, place, identity, and recurring runs.
- `Rivals`: lightweight weekly competition and segment ownership.
- `Share latest run`: converts a saved local activity into a social object.

## Current iOS Shape

- `Domains/Social/SocialHomeView.swift` owns the production Social home and Connections UI.
- `Domains/Social/TogetherStore.swift` and `TogetherContracts.swift` still retain their earlier internal names while owning API-backed Social home, connection, invitation, referral, and Cheer state; rename these after external behavior stabilizes rather than maintaining a second store.
- `Features/Simplified/SimplifiedAppShell.swift` owns the `Social · Today · Me` tab shell and routes Today's social invitation into Social.

- `Social/ActivityFeedView.swift` owns the local social hub UI.
- `Social/SocialModels.swift`, `Social/SocialSeed.swift`, `Social/SocialStore.swift`, and `Social/SocialRecognitionStore.swift` own Social-only models, seed data, interaction state, and Social-only recognition awards.
- The Social module is behind the `OUTBOUND_ENABLE_SOCIAL` Swift compilation condition.
- Beta/App Review builds should leave that flag unset until server moderation, developer response ownership, user contact, and backend social ownership are ready.
- The current implementation is local/seeded UI state. It does not call a backend yet.
- It reads `ActivityStore.activities.first` to offer the latest saved activity as a share card.
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

## Backend Contracts To Add Later

- Social identity and friend graph.
- Feed post creation from `SavedActivity` plus optional photos.
- Cheer/comment mutations.
- Club membership and club run schedule.
- Live relay presence and route invitations.
- Weekly rivalry leaderboard and segment claims.
