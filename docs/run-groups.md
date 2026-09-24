# Social Groups

Open this when designing or building Group creation, private motivation Groups, community run Groups, membership, weekly focus, notices, scheduled runs, discovery, or moderation.

Status: recommended target product and technical contract, pending owner acceptance. The consolidated model is not implemented yet. The current `Circle` and `Club` implementations are migration inputs, not parallel products to preserve.

## Product Decision

Consolidate Circle and Group into one user-facing **Group** product, one Social destination, one API family, and one persistence model.

- A private motivation Group carries forward Circle's weekly focus, optional commitments, workout contributions, and preset Cheers.
- A community run Group carries forward Group discovery and membership, then adds notices, administration, and scheduled runs.
- Creation starts from `Stay motivated together` or `Organize runs`. These are editable templates that choose safe defaults, not permanent entity types.
- Features are independent capabilities. A Group may enable weekly focus, notices, or scheduled runs without being re-created.
- A server-owned trust policy remains a hard security boundary. It is not a marketing label and does not grant administrative authority.
- `Circle` stops being a destination, entity, API namespace, analytics namespace, and user-facing noun after migration.

This replaces the earlier recommendation to share a domain layer while keeping Circle and Group as separate products.

## Why Consolidate

- Runners should not have to decide whether the same people belong in a Circle or a Group before they can invite them.
- Both products already need the same container, membership, invitation, role, event, notification, management, analytics, and offline-cache machinery.
- Social currently spends two of five top-level destinations on overlapping collections of people.
- A single Group can grow in capability without forcing members to recreate relationships or learn a second noun.
- The meaningful distinction is not group size or formality. It is whether membership implies trusted workout sharing or community coordination among people who may be strangers.

The alternatives are weaker:

- Keeping two products preserves the safest existing data defaults but permanently duplicates navigation, creation, management, and language.
- Merging only the UI leaves two authorization and persistence systems behind one screen, making mutations, invitations, badges, and cache behavior harder to reason about.
- A `circle` versus `club` type enum merely moves the product split into the database and makes later capability changes a migration.

## Product Vocabulary

- **Group**: the only user-facing relationship container.
- **Private Group**: invite-only Group whose active members are accepted connections and may share detailed workout context.
- **Community Group**: unlisted or public Group that may contain strangers and never exposes ordinary member workout details.
- **Featured**: Plainstride has chosen to highlight the Group. This is editorial treatment only.
- **Verified organization**: Plainstride has reviewed an external identity claim. Verification never grants application permissions.
- **Owner**, **admin**, and **member**: the only authorization roles in the first version.

Do not use `official`, `formal`, `club`, or `Circle` as overloaded state. Editorial curation, organization verification, trust, discovery, and authorization are separate fields.

## Safety Model

One entity does not mean one data-access policy. Every Group has a server-owned `trustPolicy`:

| Rule | `trusted_private` | `community` |
| --- | --- | --- |
| Visibility | Private only | Unlisted or public |
| Joining | Invitation only | Invitation, request, or open |
| Member eligibility | Accepted connections, block-free | Any eligible account, block-free |
| Ordinary workout detail | Visible to active members | Never returned |
| Weekly focus and contributions | Allowed | Disabled |
| Directory discovery | Never | Optional |
| Notices and scheduled runs | Optional | Optional |
| Typical creation template | Stay motivated together | Organize runs |

Server invariants:

- `trusted_private` requires `visibility = private`, `joinPolicy = invite_only`, and accepted connections for every active membership.
- Community responses never select or serialize member activity title, timing, distance, route, heart rate, energy, plan, readiness, or health context.
- `GroupContribution`, personal commitments, and workout-based Cheers exist only for `trusted_private` Groups.
- Community momentum comes only from Group-owned activity events and aggregate RSVP/result state. It never scans or links members' unrelated activities.
- Roles authorize management. Trust policy, verification, featured status, and creation template never do.
- Blocks override discovery, membership, member lists, notices, events, and mutations in both directions.
- Trust-policy conversion is deferred. The MVP does not broaden a private Group into a community Group or expose its history to a new audience.

Use separate server projection functions for trusted-private and community detail. Do not fetch private workout fields and remove them after serialization.

## Capabilities

Capabilities describe what members can do and remain independent of the trust policy where safe.

| Capability | Purpose | Default: motivation template | Default: organize-runs template |
| --- | --- | --- | --- |
| Weekly focus | Shared weekly theme and optional personal commitments | On | Off and unavailable for community trust |
| Workout contributions | Count qualifying saved activities and show trusted detail | On | Off and unavailable for community trust |
| Preset Cheers | Encourage a trusted member's contribution | On | Off |
| Notices | Owner/admin broadcast with no replies | Off | On |
| Scheduled runs | Group-owned activity events and recurring schedule later | On | On |

Capabilities can be enabled later only when the trust-policy invariants allow them. UI labels explain the job, not the implementation flag.

## Information Architecture

Social has four destinations after consolidation:

`Feed · People · Groups · Routes`

- Remove the separate Circle tab and sealed-huddle destination icon.
- Groups opens to `Your groups`, with pending invitations and join requests requiring the viewer's action first.
- A compact `Discover` section follows for public community Groups; search by name and city expands into a paginated directory.
- The account's primary motivation Group appears first in `Your groups`.
- Cards use plain badges such as `Private`, `Featured`, or `Verified`; never infer authority from those badges.
- One Create/Add action says `Create Group` everywhere in Social.
- The Groups badge combines unresolved invitations, owner/admin join requests, and unread notices. It does not mirror the chronological notification inbox.

## Creation UX

`Create Group` first asks one human question:

### Stay motivated together

- Promise: share progress and encourage a few people you trust.
- Defaults: `trusted_private`, private, invitation-only, weekly focus/contributions/Cheers enabled, scheduled runs enabled, notices disabled.
- The tailored form asks for at least one accepted connection and an optional name. It may generate and store a localized name.
- After creation, show invited people, explain that qualifying workouts are visible inside this private Group, and offer `Choose a weekly focus` or `Open Group`.

### Organize runs

- Promise: coordinate a crew, publish updates, and plan runs.
- Defaults: `community`, unlisted, request-to-join, notices and scheduled runs enabled, weekly focus/contributions/Cheers disabled.
- The tailored form asks for a name, optional description and city, and optional initial invitations. It does not require a first notice or run.
- After creation, offer `Plan a run`, `Post an update`, or `Invite people`.

The choice is a template, not stored authority. Management shows the resulting settings and capabilities. Advanced settings do not expose invalid combinations.

Use one scrollable form after template selection rather than a multi-step configuration wizard. API results use transient toast feedback unless the result requires action.

## Group Detail UX

Every detail screen shares:

1. Name, privacy/verification badges, member count, and membership action.
2. About text and the next scheduled run when present.
3. Enabled capability modules.
4. Members and management/reporting entry points.

Trusted-private detail leads with:

1. Current weekly focus and the viewer's optional commitment.
2. Member progress, recent authorized workout context, and preset Cheer.
3. `Plan a run` and upcoming activity events.
4. Recent supportive moments and settings.

Community detail leads with:

1. Pinned notice and unread notices.
2. Upcoming Group runs and RSVP state.
3. About, join policy, and member list with role and coarse presence only.
4. Owner/admin management or member report, mute, and leave controls.

Community detail has no general member activity feed. Completed Group runs may show participants and results only through the existing activity-event and connection-visibility rules.

## Today And Post-Activity

- Today may show one primary motivation Group using the existing Circle eligibility and priority behavior.
- The card says Group, not Circle, and answers only current focus, viewer contribution, and next useful action.
- Imminent joined activity events keep their existing priority.
- A saved activity reconciles into every eligible trusted-private Group by activity start time. Community membership alone never links the activity.
- Post-activity copy may say `You moved <Group name> forward` and summarize additional eligible Groups without stacking celebration screens.

## Membership And Administration

- Roles are `owner`, `admin`, and `member`.
- User-created Groups always have exactly one active owner. System-curated Groups use an explicit `managementMode = system` instead of a fake owner.
- Owners may edit settings, manage capabilities, approve requests, invite/remove members, promote/demote admins, transfer ownership, archive, and reactivate.
- Admins may manage members, notices, and runs but cannot transfer ownership or change trust policy.
- Members may leave, mute optional notifications, report the Group or content, and block another member.
- Owners cannot leave until they transfer ownership or archive the Group.
- Removal, leaving, and blocking revoke future access immediately.
- Archiving preserves history but prevents new invitations, notices, and runs.
- Ownership recovery without the current owner is an operator action and is deferred until a secure recovery policy exists.

## Notices And Attention

A notice is an owner/admin broadcast for schedule changes, meetup information, cancellations, or other concise updates.

- Notices have bounded optional title and body, one optional structured activity-event reference, pin state, publish/edit/delete timestamps, and no replies or attachments in the MVP.
- One `GroupNoticeRead(groupId, userId, lastSeenNoticeId)` watermark per active member drives unread state.
- Do not create one `SocialNotification` row per member for informational notices.
- Optional notice push delivery queries eligible, unmuted device tokens directly and routes to Group detail; it does not create a durable inbox record.
- Join requests, invitation acceptance, ownership transfer, and targeted run invitations remain per-recipient durable notifications because they require personal action or confirm a personal state change.
- Notice bodies never enter push payloads or analytics.

## Scheduled Runs

- `ActivityEvent.groupId` is the only Group source relation. Remove `sourceCircleId` and `clubId` during migration.
- Owner/admin may create Group-visible runs; a trusted-private Group may also allow members when configured.
- Exact meetup coordinates are visible only to joined or explicitly invited participants.
- Non-members may see a public run summary as a reason to join but never participant identities or coordinates.
- RSVP, attendance intent, recording, and reconciliation remain governed by the existing activity-event contract.
- Never infer physical attendance from GPS.
- Recurring series follows single-event support and must distinguish `this instance`, `this and following`, and `entire series` edits.

## Technical Model

Use `SocialGroup` as the Prisma model name to avoid SQL and language ambiguity while the API and UI say Group.

### Core

- `SocialGroup`: owner, management mode, name, slug, description, city, trust policy, visibility, join policy, lifecycle, featured state, organization verification state, capability flags, capacity snapshot, timestamps.
- `GroupMember`: group, user, role, status, notification preference, display snapshots, joined/removed timestamps.
- `GroupInvitation`: sender, recipient, status, expiry, and idempotency key.
- `GroupJoinRequest`: requester, status, reviewer, decision timestamp, and idempotency key.
- `GroupNotice` and `GroupNoticeRead`.

### Motivation capabilities

- `GroupWeek`: interval, timezone, reset weekday, focus configuration, and history.
- `GroupCommitment`: one member's optional activity-count commitment for one week.
- `GroupContribution`: unique Group-week/activity relation, permitted only for trusted-private Groups.
- `GroupCheer`: preset sender/recipient encouragement scoped to a Group week.
- `User.primaryMotivationGroupId`: account-owned Today selection.

### Coordination capabilities

- `ActivityEvent.groupId`: Group attribution and authorization source.
- `GroupRunSeries`: deferred until single Group events are stable.

Do not add a generic JSON permissions field. Stable capabilities and policies must be typed, validated, and queryable.

## Authorization And Read Projections

Every Group route resolves, in order:

1. Authenticated viewer.
2. Group lifecycle and visibility.
3. block relationship in both directions where another member is involved.
4. membership status and role.
5. trust-policy invariant.
6. capability required by the operation.

Return one common Group envelope with a policy-specific detail payload:

- `trusted`: weekly focus, commitments, contributions, recent authorized activity, Cheers.
- `community`: notices, join state, scheduled runs, and coarse member data.

The community query must not select private activity or health columns. Mutation responses return canonical server state rather than asking clients to recreate policy decisions.

## API Direction

Authenticated, role-authorized, block-aware, idempotent where retried, and cursor-paginated where lists may grow:

- `GET /v1/social/groups?scope=mine|discover&query=&city=&cursor=`
- `POST /v1/social/groups` with a creation template and its tailored fields
- `GET /v1/social/groups/:id`
- `PATCH /v1/social/groups/:id`
- `POST /v1/social/groups/:id/archive` and `/reactivate`
- invitation list/send/cancel/accept/decline routes
- join-request create/cancel/approve/deny routes
- member remove/role/leave/ownership routes
- notice list/create/update/delete/read routes
- weekly-focus, commitment, Cheer, and primary-motivation selection routes
- `POST /v1/social/activity-events` accepts `groupId`

Remove `/v1/circles`, legacy `/clubs`, `sourceCircleId`, and Circle-specific notification destinations in the same destructive cutover. Do not maintain compatibility adapters unless explicitly requested.

## Client Direction

### iOS

- Replace `CircleStore`, Circle contracts, and the lightweight Group state in `TogetherStore` with one focused `GroupStore` and `GroupContracts` under `Domains/Social`.
- Remove `.circle` from `SocialFeatureTab`; keep `.groups` as the only destination.
- Render detail modules from the server's policy-specific payload, not client guesses based on member count or badges.
- Port the existing Weekly Focus, commitment, contribution, Cheer, Today, post-activity, and account-scoped cache behavior into Group naming.
- Split the current `SocialGroupsView` into Groups home, discovery, creation, detail, notices, members, and management screens.
- Clear old Circle and Group caches when authenticated account or schema version changes.
- Localize every visible string naturally in English, Simplified Chinese, and Spanish.
- Preserve Dynamic Type, VoiceOver labels, Reduce Motion, and 44-point targets.

### Android

- Consume the same policy-specific API contracts and capability rules.
- Do not recreate Circle as an Android-only destination during parity work.
- Ship Group navigation, creation, privacy projections, analytics, and moderation behavior before calling Social parity complete.

## Analytics

Measure one coherent funnel:

`Groups exposed -> creation or discovery -> invitation/request -> active membership -> capability used -> following-week return`

Typed events cover:

- Groups destination and creation-template exposure;
- creation start/completion/failure;
- invitation and join-request outcomes;
- Group opened and membership activated;
- weekly focus, commitment, contribution, and Cheer use;
- notice published/read;
- Group run created, RSVP'd, and reconciled;
- capability/settings changes;
- mute, leave, remove, block, report, archive, and ownership outcomes.

Allowed properties are bounded: entry source, template, trust policy, visibility, join policy, viewer role, enabled capability, coarse member-count bucket, outcome, and normalized failure category.

Never send Group IDs, user IDs beyond the existing analytics identity contract, names, slugs, cities, exact counts, notice text, member identities, activity IDs or facts, locations, routes, health data, custom focus text, or notification copy.

Primary success measures are invitation/request conversion, second- and fourth-week active membership, repeated capability use, Group-run participation, and saved-activity retention. Guardrails are mute, leave, block, report, creation abandonment, and qualitative confusion or pressure feedback.

## Moderation And Privacy

- Group names, descriptions, custom focus text, notices, profiles, and public run summaries are user-generated content and inherit the filtering, reporting, blocking, deletion, contact, and response-ownership requirements in `docs/social.md`.
- A public profile shows no Group memberships by default.
- Unlisted Groups are absent from discovery and accessible only by valid invitation or share link.
- Meeting coordinates are never visible to the general Group membership without RSVP or invitation.
- Verification evidence, reports, and moderation notes are operator-only and never enter normal Group responses.
- Individual workout visibility remains governed by trust policy and connection/activity-post rules, not Group membership alone.

## Migration And Rollout

The project policy permits a destructive data reset. Prefer a clean cutover over a permanent compatibility layer.

1. Add the unified schema and authorization/projection services.
2. Replace Circle and Club APIs with the unified Group API; wire `ActivityEvent.groupId`.
3. Destructively remove Circle/Club data, run the documented schema rebuild, and reseed curated community Groups with `managementMode = system`.
4. Ship the consolidated iOS Groups destination and clear incompatible local caches.
5. Verify private motivation behavior, community privacy, notice attention, event authorization, analytics allowlists, localization, and accessibility.
6. Complete Android parity against the unified contract.
7. Add recurring runs, organization verification, and operator recovery only after the core model is stable.

Document the local rebuild command and the Cloud Run schema job from `docs/backend-deploy.md` in the implementation change. Do not preserve old Circle/Club rows unless the user explicitly requests a migration.

## Acceptance Criteria

- Social presents one Groups destination and no Circle destination.
- A runner can create either template without learning a second entity name.
- Motivation-template Groups preserve weekly focus, optional commitments, qualifying contributions, authorized workout context, preset Cheers, Today presentation, and post-activity acknowledgement.
- Organize-runs Groups support unlisted creation, invitations or join requests, notices, member administration, and Group-owned activity events.
- Public discovery returns only community Groups.
- No community response or aggregate links an ordinary member workout or exposes workout, route, health, plan, or companion data.
- Server validation rejects every invalid trust-policy, visibility, join-policy, and capability combination.
- Featured and verified states never change authorization.
- Notice unread state uses a member watermark; informational notice pushes do not create per-recipient durable inbox rows.
- Ownership transfer, leave, remove, mute, archive, report, and block work and return canonical state.
- All new user-facing strings are localized and all behavior changes use the bounded analytics contract.
- Backend, iOS, and Android build-only verification succeeds for the slices each implementation changes.

## Deferred

- Trust-policy conversion between private and community audiences.
- Group chat, direct messages, and notice comments.
- General member activity feeds for community Groups.
- Leaderboards, rankings, points, levels, and streak punishment.
- Recurring run series until single Group runs are stable.
- Capacity limits and waitlists for Group runs.
- Public web pages and SEO.
- Dues, sponsorships, treasury, or other money movement.
- Organization verification operations, waiver capture, affiliation lookup, and liability records.
- Automated moderation classification and a full operator console.
- Ownerless self-service recovery.
