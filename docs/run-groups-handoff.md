# Social Groups — Handover Brief

Read `docs/run-groups.md` for the canonical target product and technical contract. This brief records the decision and the work that remains; it is not a second source of product rules.

## Decision

- Consolidate Circle and Group into one user-facing **Group** product, one Social destination, one API family, and one persistence model.
- Preserve two server-enforced trust policies: `trusted_private` may share detailed workout context among accepted connections; `community` may include strangers and never exposes ordinary member workout data.
- Creation offers two editable templates: `Stay motivated together` and `Organize runs`. Templates choose safe defaults but do not authorize actions or become permanent entity types.
- Weekly focus, workout contributions, preset Cheers, notices, and scheduled runs are capabilities on a Group.
- Remove Circle as a destination and noun during the destructive cutover; do not maintain Circle and Club compatibility layers unless explicitly requested.

## Why

- The two current products duplicate container, membership, invitation, event, notification, management, analytics, and cache behavior.
- Social currently exposes separate Circle and Groups destinations for overlapping collections of people.
- A UI-only merge would hide two authorization systems behind one screen and make the product harder to maintain.
- A completely uniform access policy would be unsafe. The trust-policy boundary keeps private workout sharing out of community queries by construction.

## Current Implementation

- Circle is the mature private-motivation vertical: weekly focus, commitments, contributions, Cheers, invitations, ownership, Today presentation, post-activity acknowledgement, notifications, and account-scoped caching.
- Group is a minimal `Club`/`ClubMembership` directory with discoverable join/leave and no creation, detail, administration, notices, or writable activity-event attribution.
- Social currently has separate Circle and Groups tabs.
- `ActivityEvent` has both `sourceCircleId` and `clubId`; only the Circle source is writable.
- None of the consolidated schema, API, or client design is implemented yet.

## Implementation Order

1. Build the unified `SocialGroup` schema and separate trusted/community authorization projections.
2. Port Circle's private-motivation behavior into Group services and routes.
3. Add community creation, membership requests, roles, notices, moderation, and `ActivityEvent.groupId`.
4. Destructively remove Circle/Club data and reseed system-managed community Groups.
5. Replace the separate iOS Circle and Groups destinations with the consolidated Groups UX and clear incompatible caches.
6. Verify analytics privacy, localization, accessibility, notice attention, and community data projections.
7. Complete Android parity against the same contract.

Do not begin by sharing serializers or generalizing the current Circle contribution reconciler. Community queries must never load private workout fields, and community membership must never attach an unrelated personal activity.

## Key Pointers

- `docs/run-groups.md` — canonical consolidated product, UX, privacy, data, API, client, analytics, rollout, and acceptance contract.
- `docs/your-circle.md` — current Circle behavior and migration reference; not the future information architecture.
- `docs/social.md` — current Social and activity-event behavior plus App Review obligations.
- `docs/notifications.md` — durable notification and routing contract.
- `docs/product-analytics.md` — typed provider-neutral analytics rules.
- `docs/backend-deploy.md` — deployed schema job for the destructive cutover.
