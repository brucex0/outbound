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

- `Social/ActivityFeedView.swift` owns the first-pass local social hub.
- The current implementation is local/seeded UI state. It does not call a backend yet.
- It reads `ActivityStore.activities.first` to offer the latest saved activity as a share card.
- Feed cards use route previews, social actions, and seeded people so interaction patterns are visible while backend APIs are still absent.

## Backend Contracts To Add Later

- Social identity and friend graph.
- Feed post creation from `SavedActivity` plus optional photos.
- Cheer/comment mutations.
- Club membership and club run schedule.
- Live relay presence and route invitations.
- Weekly rivalry leaderboard and segment claims.
