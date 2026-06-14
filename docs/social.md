# Social

Open this when changing the Social tab, social graph concepts, feed cards, clubs, relays, challenges, or rivalry loops.

## Product Direction

Social is the app's network-effect surface. It should make runs feel shared, timely, and worth returning to even before a user starts recording.

Core loops:

- `Squad`: friends' runs, live relays, cheers, comments, and route prompts.
- `Clubs`: opt-in groups around time, place, identity, and recurring runs.
- `Rivals`: lightweight weekly competition and segment ownership.
- `Share latest run`: converts a saved local activity into a social object.

## Current iOS Shape

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
