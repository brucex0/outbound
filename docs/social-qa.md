# Social QA

## 2026-10-08 planned activity regression

- Restored Start activity and Share live map eligibility for known organizers and joined participants when a response lacks `canParticipate`; an explicit server denial remains authoritative. Both controls use the same eligibility rule.
- Group activity labels explicitly use the `GroupActivity` localization table, including participant counts, results, companion attribution, and live-map failures.
- Camera and map recording pages expose an expandable event participant panel independently of optional live-location sharing. It refreshes every 15 seconds and includes participants who have not started.
- Saved recordings take their event ID from the session intent rather than a second transient store value. Today and Me recent cards show the group marker; saved detail retains actual-participant companion attribution. Unlinked Quick Run recordings are not retroactively assigned to an event.
- `group_activity_presence_viewed` records only a participant-count bucket, once per mounted participant panel; no event IDs or names are collected.
- Verification: Simulator build and compiled English/Spanish/Simplified Chinese catalog entries; no test suite or physical-device UI pass.

## 2026-10-04 feed layout follow-up

- The retained collection view still showed its section header and cards overlapping before a scroll despite post-snapshot layout invalidation.
- Replaced the hosted collection cells with a retained SwiftUI `ScrollView` and `LazyVStack`; visited feature tabs stay mounted to preserve the feed position across detail navigation.
- Constrained the app launch mark to its splash frame and clipped it to prevent the source image from escaping the page bounds.
- Build-only validation succeeds; visual verification on device remains outstanding.

## 2026-09-27 iOS feed crash review

- Retrieved two matching `Outbound` crash reports from Bruce main (4:05 PM and 4:07 PM): both were main-thread `SIGTRAP` crashes in repeated `UICollectionView` visible-cell/layout updates, not jetsam terminations.
- Replaced the feed's compositional layout with a full-width self-sizing flow layout and an explicit width-constrained cell measurement path.
- The changed Swift file type-checks and the full iOS Simulator app build succeeds. Simulator services stopped responding during this pass, so scrolling could not be re-exercised in Simulator; device verification remains outstanding.

## 2026-09-27 iOS feed review

- Reviewed feed row structure, root tasks, hidden tabs, refresh/pagination races, preview preparation, and app foreground handling.
- Replaced SwiftUI scroll restoration with a retained UIKit collection view whose unchanged model updates leave layout untouched.
- Manually exercised a temporary 60-card fixture with alternating photos/routes and varying caption heights in an isolated iPhone 17 simulator: direct-touch detail returns at deep offsets, repeated returns on the same route card, screen lock/unlock, header profile links, author profile links, and native pull-to-refresh. The visible position matched before and after the direct-touch returns and lock/unlock.
- Accessibility-driven clicks can scroll a partially visible target into view before tapping; direct touch coordinates were used for the position comparison.
- Temporary fixture code was removed. Simulator compilation is the basic check; no test suite or physical-device frame-pacing trace was run.

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
