# Social QA

## 2026-08-14 regression pass

Tested the current Social implementation with the seeded iOS UI fixture and the local Firebase Auth, API, and PostgreSQL stack.

### Product defects reported

- Connection-request Accept and Decline text buttons occupied too much row space. The current candidate uses compact icon actions with explicit accessibility labels.
- Tapping Accept appeared to do nothing when the connection update succeeded but optional notification creation failed against an older database schema. The current candidate isolates the optional notification failure and immediately reflects successful mutations in client state.

### Automated coverage maintained

- Seeded iOS UI: feed, Cheer toggle, comments, group-run detail, RSVP, connections, Accept, Decline, group discovery and joining, notifications, and invitation acceptance.
- Real server: authenticated Social home, people search, connection Accept/removal, group join/leave, RSVP leave/join, Cheer removal/addition, comment creation/deletion, reports, notification read state, invitation acceptance, targeted invitations, referrals, block/unblock, and activity sharing with a second authenticated persona.

### Test-suite issues corrected

- Made UI launches deterministic when onboarding state survives between simulator runs.
- Updated navigation for the Social community menu and accessibility locators for icon actions.
- Removed the obsolete manual activity-share assertion after synced activities began sharing automatically.

### Remaining gaps

- Automated UI tests validate icon accessibility labels and behavior, but not precise rendered button dimensions. Continue visual review on compact and accessibility text sizes.
- Local server tests use the latest schema. Schema-upgrade compatibility must also be checked in deployment verification when production migrations lag application code.
- Push delivery is not covered; the in-app notification inbox is covered.
