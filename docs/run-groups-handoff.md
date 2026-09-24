# Social Groups — Handover Brief

Read `docs/run-groups.md` for the canonical target product and technical contract. This brief records the decision and the work that remains; it is not a second source of product rules.

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

## Current Implementation

- Circle is the mature private-motivation vertical: weekly themes, commitments, contributions, Cheers, invitations, ownership, post-activity acknowledgement, notifications, and account-scoped caching. Its Group container and primary-selection behavior on Today are not carried forward.
- The public consolidation slice is implemented: one iOS Groups destination, no Circle container on Today, Group terminology and Weekly Theme copy, account-scoped Group cache reset, and localized Group copy on Android.
- `GET /v1/social/groups` now projects private memberships and discoverable community Groups together, with owner/city context for duplicate names. Private Group mutations are also reachable under `/v1/social/groups`; the old `/v1/groups` mount is a migration seam.
- Activity events accept the generic `activityType` set and `sourceGroupId`, and private or community membership can authorize the source. Responses expose one generic Group source while legacy storage fields remain internal.
- Analytics includes Group exposure/open/membership events, and Android Social renders the unified projection instead of separate Circle and community collections.
- The persistence layer is not yet cut over: Prisma still has Circle/Club tables and `ActivityEvent.sourceCircleId`/`clubId`; community creation, join requests, notices, share-link tokens, and full Group administration are still migration work.

## Implementation Order

1. Build the unified `SocialGroup` schema and migrate private/community authorization projections.
2. Add community creation, join requests, roles, notices, moderation, and revocable Group invite links.
3. Replace legacy `ActivityEvent.sourceCircleId`/`clubId` with `groupId` and remove Circle-specific notification destinations.
4. Destructively remove Circle/Club data and reseed system-managed community Groups.
5. Rename internal Circle stores/contracts and finish analytics/localization cleanup after the schema cutover.
6. Verify privacy, accessibility, notice attention, and deep-link behavior, then complete Android parity against the final contract.

Do not begin by sharing serializers or generalizing the current Circle contribution reconciler. Community queries must never load private workout fields, and community membership must never attach an unrelated personal activity.

## Key Pointers

- `docs/run-groups.md` — canonical consolidated product, UX, privacy, data, API, client, analytics, rollout, and acceptance contract.
- `docs/your-circle.md` — current Circle behavior and migration reference; not the future information architecture.
- `docs/social.md` — current Social and activity-event behavior plus App Review obligations.
- `docs/notifications.md` — durable notification and routing contract.
- `docs/product-analytics.md` — typed provider-neutral analytics rules.
- `docs/backend-deploy.md` — deployed schema job for the destructive cutover.
