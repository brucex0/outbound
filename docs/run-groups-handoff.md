# Social Groups — Implementation Record

Read `docs/run-groups.md` for the canonical product and technical contract. This record describes the completed destructive consolidation and is not a second source of product rules.

## Decision

- Consolidate Circle and Group into one user-facing **Group** product, one Social destination, one API family, and one persistence model.
- Preserve two server-enforced trust policies: `trusted_private` may share detailed workout context among accepted connections; `community` may include strangers and never exposes ordinary member workout data.
- Creation offers two editable templates: `Stay motivated together` and `Organize activities`. Templates choose safe defaults but do not authorize actions or become permanent entity types.
- Weekly Theme, workout contributions, preset Cheers, notices, and scheduled activities are capabilities on a Group.
- The product is activity-generic; running, walking, hiking, cycling, swimming, strength, and open/mixed activities use the same Group event model.
- Today never shows a Group container. Only an activity event the viewer is participating in may surface there alongside their own planned workout and existing recording/start affordances.
- Display names are non-unique. Stable IDs identify Groups, and revocable opaque tokens identify invitation links.
- Remove Circle as a destination and noun during the destructive cutover; do not maintain Circle and Club compatibility layers unless explicitly requested.

## Why

- The two current products duplicate container, membership, invitation, event, notification, management, analytics, and cache behavior.
- Social currently exposes separate Circle and Groups destinations for overlapping collections of people.
- A UI-only merge would hide two authorization systems behind one screen and make the product harder to maintain.
- A completely uniform access policy would be unsafe. The trust-policy boundary keeps private workout sharing out of community queries by construction.

## Implemented State

- One `SocialGroup` persistence model, typed membership/invitation/request/link/notice/motivation relations, and `ActivityEvent.groupId` are the only Group storage contract.
- `/v1/social/groups` owns mine/discovery/detail, creation templates, membership, administration, notices, motivation capabilities, activity attribution, and opaque invite links. `/v1/groups`, `/clubs`, and legacy adapters are removed.
- Trusted-private and community reads are separate projections. Community responses never select member workout fields.
- iOS and Android use Group stores/repositories, Group notification destinations, account-scoped offline state, and localized Group terminology.
- Rebuilds are intentionally destructive before release; legacy rows, caches, and seed identities are not migrated.

## Rebuild / Verification

1. Run `cd backend && npm run db:rebuild` locally, or run the documented Cloud Run schema job against a disposable database.
2. Run the seed command after the rebuild to create system-managed public Groups.
3. Run backend, iOS, Android phone, and Wear build-only verification; do not run the test suite unless explicitly requested.

The implementation keeps private and community projections separate. Community queries do not select member workout fields, and community membership never attaches unrelated personal activity. This file is retained as an implementation record; `docs/run-groups.md` remains the only product contract.

## Key Pointers

- `docs/run-groups.md` — canonical consolidated product, UX, privacy, data, API, client, analytics, rollout, and acceptance contract.
- `docs/your-circle.md` — archived pre-consolidation behavior reference; not a runtime or product contract.
- `docs/social.md` — current Social and activity-event behavior plus App Review obligations.
- `docs/notifications.md` — durable notification and routing contract.
- `docs/product-analytics.md` — typed provider-neutral analytics rules.
- `docs/backend-deploy.md` — deployed schema job for the destructive cutover.
