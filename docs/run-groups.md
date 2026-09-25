# Social Groups

Open this when designing or building Group creation, private motivation Groups, community activity Groups, membership, weekly themes, notices, scheduled activities, discovery, or moderation.

Status: implemented unified Group contract. The destructive pre-release cutover uses `SocialGroup` and the `Group*` relations below; rebuild local or deployed databases from the final Prisma schema before seeding.

## Product Decision

Consolidate Circle and Group into one user-facing **Group** product, one Social destination, one API family, and one persistence model.

- A private motivation Group carries forward Circle's weekly theme, optional commitments, workout contributions, and preset Cheers.
- A community activity Group carries forward Group discovery and membership, then adds notices, administration, and scheduled activities.
- Creation starts from `Stay motivated together` or `Organize activities`. These are editable templates that choose safe defaults, not permanent entity types.
- Features are independent capabilities. A Group may enable a weekly theme, notices, or scheduled activities without being re-created.
- A server-owned trust policy remains a hard security boundary. It is not a marketing label and does not grant administrative authority.
- `Circle` stops being a destination, entity, API namespace, analytics namespace, and user-facing noun after migration.

This replaces the earlier recommendation to share a domain layer while keeping Circle and Group as separate products.

## Why Consolidate

- People should not have to decide whether the same relationships belong in a Circle or a Group before they can invite them.
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

## Names And Identity

- Group display names are not globally unique. Common names such as `Morning Crew` are legitimate in different places and relationships.
- The immutable `SocialGroup.id`, never the name, is the database and API identity.
- Invitation and share links use a revocable, unguessable token such as `/invite/group/:token`; they do not use the display name or a user-chosen slug.
- Store a normalized, indexed name only for case- and compatibility-insensitive search; do not place a uniqueness constraint on it. Private Groups never enter search.
- Creation accepts an idempotency key so a retry cannot create an accidental duplicate. Name uniqueness is not used as retry protection.
- Lists and search disambiguate duplicate names with the Group image or member avatars, privacy badge, city when supplied, organizer or mutual-member context when authorized, and member count.
- Never append an artificial numeric suffix to the displayed name. If two results remain visually identical, their surrounding authorized context and stable destination still distinguish them.
- Renaming a Group does not change its ID, invitation links, memberships, events, or history.
- Public vanity URLs and SEO slugs are deferred. If added later, their uniqueness is a routing concern and never makes the display name unique.

## Safety Model

One entity does not mean one data-access policy. Every Group has a server-owned `trustPolicy`:

| Rule | `trusted_private` | `community` |
| --- | --- | --- |
| Visibility | Private only | Unlisted or public |
| Joining | Invitation only | Invitation, request, or open |
| Member eligibility | Accepted connections, block-free | Any eligible account, block-free |
| Ordinary workout detail | Visible to active members | Never returned |
| Weekly theme and contributions | Allowed | Disabled |
| Directory discovery | Never | Optional |
| Notices and scheduled activities | Optional | Optional |
| Typical creation template | Stay motivated together | Organize activities |

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

| Capability | Purpose | Default: motivation template | Default: organize-activities template |
| --- | --- | --- | --- |
| Weekly theme | Shared intention and optional personal commitments for the current week | On | Off and unavailable for community trust |
| Workout contributions | Count qualifying saved activities and show trusted detail | On | Off and unavailable for community trust |
| Preset Cheers | Encourage a trusted member's contribution | On | Off |
| Notices | Owner/admin broadcast with no replies | Off | On |
| Scheduled activities | Group-owned activity events and recurring schedule later | On | On |

Capabilities can be enabled later only when the trust-policy invariants allow them. UI labels explain the job, not the implementation flag.

## Information Architecture

Social has four destinations after consolidation:

`Feed · People · Groups · Routes`

- Remove the separate Circle tab and sealed-huddle destination icon.
- Groups opens to `Your groups`, with pending invitations and join requests requiring the viewer's action first.
- A compact `Discover` section follows for public community Groups; search by name and city expands into a paginated directory.
- `Your groups` orders unresolved actions first, then recent Group activity; there is no primary Group concept.
- Cards use plain badges such as `Private`, `Featured`, or `Verified`; never infer authority from those badges.
- One Create/Add action says `Create Group` everywhere in Social.
- The Groups badge combines unresolved invitations, owner/admin join requests, and unread notices. It does not mirror the chronological notification inbox.

## Creation UX

`Create Group` first asks one human question:

### Stay motivated together

- Promise: share progress and encourage a few people you trust.
- Defaults: `trusted_private`, private, invitation-only, weekly theme/contributions/Cheers enabled, scheduled activities enabled, notices disabled.
- The tailored form asks for at least one accepted connection and an optional name. It may generate and store a localized name.
- After creation, show invited people, explain that qualifying workouts are visible inside this private Group, and offer `Choose a weekly theme` or `Open Group`.

### Organize activities

- Promise: coordinate a community, publish updates, and plan activities.
- Defaults: `community`, unlisted, request-to-join, notices and scheduled activities enabled, weekly theme/contributions/Cheers disabled.
- The tailored form asks for a name, optional description, city, activity interests, and initial invitations. It does not require a first notice or activity.
- Activity interests such as running, walking, hiking, cycling, swimming, strength, or mixed improve discovery but never restrict which activities the Group may schedule.
- After creation, offer `Plan an activity`, `Post an update`, or `Invite people`.

The choice is a template, not stored authority. Management shows the resulting settings and capabilities. Advanced settings do not expose invalid combinations.

Use one scrollable form after template selection rather than a multi-step configuration wizard. API results use transient toast feedback unless the result requires action.

## Group Detail UX

Every detail screen shares:

1. Name, privacy/verification badges, member count, and membership action.
2. About text and the next scheduled activity when present.
3. Enabled capability modules.
4. Members and management/reporting entry points.

Trusted-private detail leads with:

1. Current weekly theme and the viewer's optional commitment.
2. Member progress, recent authorized workout context, and preset Cheer.
3. `Plan an activity` and upcoming activity events.
4. Recent supportive moments and settings.

Community detail leads with:

1. Pinned notice and unread notices.
2. Upcoming Group activities and RSVP state.
3. About, join policy, and member list with role and coarse presence only.
4. Owner/admin management or member report, mute, and leave controls.

Community detail has no general member activity feed. Completed Group activities may show participants and results only through the existing activity-event and connection-visibility rules.

## Today Boundary And Post-Activity

- Today never shows a Group container, weekly theme, Group progress, notice, or creation prompt.
- Today remains focused on what the person may do today: an active recording, a Group or direct activity event they are participating in, their own planned workout, and the existing quick-start affordance.
- A Group activity reaches Today only through the ordinary `ActivityEvent` contract after the viewer has joined or accepted the invitation. The card may show a share-safe `From <Group name>` source label.
- Group invitations awaiting a decision, notices, weekly themes, and general Group state remain in Social and Notification Center.
- A saved activity reconciles into every eligible trusted-private Group by activity start time. Community membership alone never links the activity.
- Post-activity copy may say `You moved <Group name> forward` when exactly one Group received a contribution. For several Groups, show one aggregate acknowledgement such as `Counted toward 3 private Groups` without choosing a primary Group or stacking celebration screens.

## Membership And Administration

- Roles are `owner`, `admin`, and `member`.
- User-created Groups always have exactly one active owner. System-curated Groups use an explicit `managementMode = system` instead of a fake owner.
- Owners may edit settings, manage capabilities, approve requests, invite/remove members, promote/demote admins, transfer ownership, archive, and reactivate.
- Admins may manage members, notices, and activities but cannot transfer ownership or change trust policy.
- Members may leave, mute optional notifications, report the Group or content, and block another member.
- Owners cannot leave until they transfer ownership or archive the Group.
- Removal, leaving, and blocking revoke future access immediately.
- Archiving preserves history but prevents new invitations, notices, and activities.
- Ownership recovery without the current owner is an operator action and is deferred until a secure recovery policy exists.

## Notices And Attention

A notice is an owner/admin broadcast for schedule changes, meetup information, cancellations, or other concise updates.

- Notices have bounded optional title and body, one optional structured activity-event reference, pin state, publish/edit/delete timestamps, and no replies or attachments in the MVP.
- One `GroupNoticeRead(groupId, userId, lastSeenNoticeId)` watermark per active member drives unread state.
- Do not create one `SocialNotification` row per member for informational notices.
- Optional notice push delivery queries eligible, unmuted device tokens directly and routes to Group detail; it does not create a durable inbox record.
- Join requests, invitation acceptance, ownership transfer, and targeted activity invitations remain per-recipient durable notifications because they require personal action or confirm a personal state change.
- Notice bodies never enter push payloads or analytics.

## Scheduled Activities

- `ActivityEvent.groupId` is the only Group source relation. Remove `sourceCircleId` and `clubId` during migration.
- Owner/admin may create Group-visible activities; a trusted-private Group may also allow members when configured.
- Each event uses a canonical activity type such as running, walking, hiking, cycling, swimming, or strength, or an explicit open/mixed policy. Group activity interests provide defaults but do not gate event types.
- Exact meetup coordinates are visible only to joined or explicitly invited participants.
- Non-members may see a public activity summary as a reason to join but never participant identities or coordinates.
- RSVP, attendance intent, recording, and reconciliation remain governed by the existing activity-event contract.
- Never infer physical attendance from GPS.
- Recurring series follows single-event support and must distinguish `this instance`, `this and following`, and `entire series` edits.

## Technical Model

Use `SocialGroup` as the Prisma model name to avoid SQL and language ambiguity while the API and UI say Group.

### Core

- `SocialGroup`: owner, management mode, non-unique display name, normalized search name, description, city, activity interests, trust policy, visibility, join policy, lifecycle, featured state, organization verification state, capability flags, capacity snapshot, timestamps.
- `GroupMember`: group, user, role, status, notification preference, display snapshots, joined/removed timestamps.
- `GroupInvitation`: sender, recipient, status, expiry, and idempotency key.
- `GroupInviteLink`: revocable opaque token digest, creator, expiry, use policy, and timestamps. Store only the digest; return the raw token once when the link is created.
- `GroupJoinRequest`: requester, status, reviewer, decision timestamp, and idempotency key.
- `GroupNotice` and `GroupNoticeRead`.

### Motivation capabilities

- `GroupWeek`: interval, timezone, reset weekday, theme configuration, and history.
- `GroupCommitment`: one member's optional activity-count commitment for one week.
- `GroupContribution`: unique Group-week/activity relation, permitted only for trusted-private Groups.
- `GroupCheer`: preset sender/recipient encouragement scoped to a Group week.

### Coordination capabilities

- `ActivityEvent.groupId`: Group attribution and authorization source.
- `GroupActivitySeries`: deferred until single Group events are stable.

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

- `trusted`: weekly theme, commitments, contributions, recent authorized activity, Cheers.
- `community`: notices, join state, scheduled activities, and coarse member data.

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
- weekly-theme, commitment, and Cheer routes
- `POST /v1/social/activity-events` accepts `groupId`

The destructive cutover removes `/v1/circles`, legacy `/clubs`, `sourceCircleId`, and Circle-specific notification destinations. No compatibility adapters are retained.

## Client Direction

### iOS

- The iOS implementation uses one focused `GroupStore` and `GroupContracts` under `Domains/Social`; the old Circle store and contracts are deleted.
- Remove `.circle` from `SocialFeatureTab`; keep `.groups` as the only destination.
- Render detail modules from the server's policy-specific payload, not client guesses based on member count or badges.
- Weekly Theme, commitment, contribution, Cheer, post-activity, and account-scoped cache behavior use Group naming; Today contains no Group container card or primary-Group state.
- Split the current `SocialGroupsView` into Groups home, discovery, creation, detail, notices, members, and management screens.
- Clear old Circle and Group caches when authenticated account or schema version changes.
- Localize every visible string naturally in English, Simplified Chinese, and Spanish.
- Preserve Dynamic Type, VoiceOver labels, Reduce Motion, and 44-point targets.

### Android

- Consume the same policy-specific API contracts and capability rules.
- Android has no separate private-motivation destination; both templates use the unified Group navigation and server policy.
- Ship Group navigation, creation, privacy projections, analytics, and moderation behavior before calling Social parity complete.

## Analytics

Measure one coherent funnel:

`Groups exposed -> creation or discovery -> invitation/request -> active membership -> capability used -> following-week return`

Typed events cover:

- Groups destination and creation-template exposure;
- creation start/completion/failure;
- invitation and join-request outcomes;
- Group opened and membership activated;
- weekly theme, commitment, contribution, and Cheer use;
- notice published/read;
- Group activity created, RSVP'd, and reconciled;
- capability/settings changes;
- mute, leave, remove, block, report, archive, and ownership outcomes.

Allowed properties are bounded: entry source, template, trust policy, visibility, join policy, viewer role, enabled capability, coarse member-count bucket, outcome, and normalized failure category.

Never send Group IDs, user IDs beyond the existing analytics identity contract, names, invitation tokens, cities, exact counts, notice text, member identities, activity IDs or facts, locations, routes, health data, custom theme text, or notification copy.

Primary success measures are invitation/request conversion, second- and fourth-week active membership, repeated capability use, Group-activity participation, and saved-activity retention. Guardrails are mute, leave, block, report, creation abandonment, and qualitative confusion or pressure feedback.

## Moderation And Privacy

- Group names, descriptions, custom theme text, notices, profiles, and public activity summaries are user-generated content and inherit the filtering, reporting, blocking, deletion, contact, and response-ownership requirements in `docs/social.md`.
- A public profile shows no Group memberships by default.
- Unlisted Groups are absent from discovery and accessible only by valid invitation or share link.
- Meeting coordinates are never visible to the general Group membership without RSVP or invitation.
- Verification evidence, reports, and moderation notes are operator-only and never enter normal Group responses.
- Individual workout visibility remains governed by trust policy and connection/activity-post rules, not Group membership alone.

## Migration And Rollout

The project policy permits a destructive data reset. Prefer a clean cutover over a permanent compatibility layer.

The destructive cutover is implemented. `backend/prisma/schema.prisma` is the replacement schema; `cd backend && npm run db:rebuild` resets and reseeds a disposable database, while `docs/backend-deploy.md` documents the equivalent Cloud Run schema job. The deployed clients use the unified Group contracts, clear account-scoped legacy caches by using the new Group cache namespaces, and expose no compatibility routers or adapters.

Verification is build-only for this release: backend TypeScript, iOS phone and Watch targets, Android phone variants, and Wear OS variants. Recurring activity series, organization verification operations, and owner recovery remain deferred below.

## Acceptance Criteria

- Social presents one Groups destination and no Circle destination.
- A person can create either template without learning a second entity name.
- Motivation-template Groups preserve weekly themes, optional commitments, qualifying contributions, authorized workout context, preset Cheers, and post-activity acknowledgement without adding a Group container to Today.
- Organize-activities Groups support unlisted creation, invitations or join requests, notices, member administration, and Group-owned activity events across supported activity types.
- Duplicate display names work throughout creation, search, invitations, membership, event attribution, rename, and deep linking because stable IDs and opaque tokens provide identity.
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
- Recurring activity series until single Group activities are stable.
- Capacity limits and waitlists for Group activities.
- Public web pages and SEO.
- Dues, sponsorships, treasury, or other money movement.
- Organization verification operations, waiver capture, affiliation lookup, and liability records.
- Automated moderation classification and a full operator console.
- Ownerless self-service recovery.
