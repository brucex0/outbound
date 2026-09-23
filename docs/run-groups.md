# Run Groups

Open this when brainstorming or building run Group creation, membership, roles, Group notices, Group runs, or Group moderation.

This is a brainstorm and design-options document. It is not yet a committed product contract. `docs/your-circle.md` remains the model for what a finished contract looks like, and `docs/social.md` remains canonical for the Social shell that hosts Groups.

## Why This Is Un-Deferred

- `docs/social.md` currently lists "Group creation and administration; launch Groups are managed/seeded" as deferred. This document is the step that un-defers it.
- Groups are the one Social destination with real-world gravity: a named local club, recurring weekly runs, an organizer who needs to broadcast. Everything else in Social is person-to-person.
- The current implementation cannot support that promise at all: groups are read-only plus join/leave, and no client can attach an activity to a group.
- Circle proves the shared machinery works (invitations, membership authorization, contributions, notifications, cheers, management, analytics, offline cache). Groups should reuse it rather than invent a second social stack.

## Current State (verified in this repository)

- Prisma `Club` is only `name`, `description`, `city`, `isDiscoverable`, `createdAt`, `updatedAt`. No owner, no join policy, no visibility, no state, no slug, no capacity.
- `ClubMembership` is only `clubId`, `userId`, `role @default("member")`, `createdAt`. No pending state, no requested/approved life cycle, no mute, no removal metadata.
- `ActivityEvent.clubId` exists and is read to label feed cards as `From <name> · Your group`, but **no route ever writes it**. `createActivityEventSchema` accepts only `sourceCircleId`, so a group-owned run is currently uncreatable from any client.
- Backend surface is read + join/leave only: `GET /v1/social/clubs`, `GET /v1/social/groups` (`isDiscoverable`, `take: 50`, no cursor), `POST`/`DELETE /v1/social/groups/:id/membership`, plus legacy `POST /v1/social/clubs/:id/join` and `DELETE /v1/social/clubs/:id/membership`.
- iOS: `SocialGroupDTO(id, name, description, city, memberCount, membershipRole)` and `SocialGroupsView`, a Joined/Discover list with one Join/Leave button per row and no detail screen.
- `seedTestPersonas.ts` creates two ownerless clubs for end-to-end tests; production launch groups are seeded the same way.
- Joining awards the `relayPlayer` recognition.
- `docs/notifications.md` keeps Groups unbadged "until their contracts expose reliable personally relevant update signals."

## What Makes A Group Different From A Circle

Keep this distinction explicit, because the failure mode is building a second Circle with a different name.

- Circle: invitation-only, capacity-snapshotted (default 6), trusted people, no leaderboard, no chat, one shared weekly theme, individual commitments, preset Cheers.
- Group: discoverable, effectively unbounded, administrator-run, includes strangers, repeats on a schedule, needs moderation and broadcast.
- Shared, not duplicated: activity events, in-app notification inbox, recognition awards, analytics contract, localization rules, transient toast feedback, account-scoped offline cache, block enforcement.
- Do not add a leaderboard, points, levels, or streak punishment to Groups. It contradicts both `docs/your-circle.md` and the product direction in `docs/product-strategy.md`.
- Neither Circle nor Group becomes chat. Notices are broadcast, not conversation.

## Two Shapes, One Model

A Group is either a formal run club or an informal run crew, and both belong in the same container. The mistake to avoid is shipping a type picker.

Why formality is a set of independent axes rather than a type:

- Creation happens before the creator knows what they are. A six-person Wednesday crew routinely becomes a dues-collecting club years later.
- A type forks every downstream feature permanently: fields, permissions, notifications, admin screens, directory rules. The result is two half-built products.
- A type is also a promotion path. With capability flags, an informal crew that grows up simply turns affordances on.
- **Formality must never grant authorization.** Anyone can type "registered club". Verification is an identity claim reviewed by a human, not a permission escalation.

| Axis | Informal crew | Formal club |
| --- | --- | --- |
| Discovery | unlisted by default | public, searchable, wants to be found |
| Identity | a typed name | verified organization, affiliation reference, logo |
| Joining | instant, or by invite link | dues, waiver, sometimes approval |
| Roles | one owner, everyone else equal | officers, secretary, treasurer, coaches |
| Schedule | episodic | season, recurring weekly series |
| Liability | the organizer's own problem | waivers and insurance, so attendance records matter |
| Continuity | dies when the founder's interest does | persists beyond any individual |
| Scale | 3-15 | 50-2,000+ |

What formal really means in the real world, and therefore what the extra surface has to support:

- External affiliation rather than self-declaration. England Athletics affiliation, for example, is a paid, approved application, and athlete registration is gated on the club being affiliated.
- Liability insurance and mandatory waivers. The RRCA requires member clubs to carry general liability coverage or prove coverage, and to obtain waivers of liability from members and participants at join and renewal.
- Dues and a treasury, plus a registered-athlete relationship between a person and the club.
- Officer structure and volunteer roles that outlive any single account.

Two consequences that are easy to miss:

- **Continuity.** A formal club is an institution that outlives its admins, so ownership must be transferable and should eventually attach to an organization identity rather than a personal account. An informal crew is usually one person's contact list, so it silently dies if that person changes jobs or moves unless transfer and stale-owner recovery are easy. Ownership transfer is therefore an MVP requirement, not an admin nicety.
- **Liability.** If Plainstride becomes the system of record for who RSVP'd and who showed up at a club run, waiver acknowledgement becomes a real product question. Decide explicitly whether to store it or to stay out of it.

Sequencing:

- Build the informal shape first. Crews are the growth loop: colleagues and neighbors already share a channel, so invitation conversion is high and the cost is low because it maps onto the existing connection, activity-event, notification, and Circle contribution machinery.
- Treat verified clubs as a supply play. Few accounts, many users each, and the segment most likely to pay for organizer tooling — but they cost verification, waivers, dues, public pages, and moderation. Add those affordances when a real club asks, not before.
- Do not put informal crews into public discovery. Discoverability is its own axis and defaults to off.
- Do not promise dues collection in the MVP. Charging for a real-world club is a payments, tax, and store-review question rather than a schema change, and it must be resolved before any in-app money movement is designed.

User-facing vocabulary stays one noun. Formality appears as a plain-language descriptor plus, only after review, a verified badge.

## Product Model (proposal)

- A Group is a persistent container with one owner, optional admins, and members.
- Fields: display name, unique-ish share slug, description, city, activity focus (road / trail / track / mixed), join policy, discoverability, activity-event attribution, lifecycle (`active` / `archived`).
- Roles: `owner`, `admin`, `member`. `ClubMembership.role` already defaults to `member`, so the column exists and only needs meaning.
- Membership has a state, not just a row: `pending`, `active`, `left`, plus removal caused by an admin.
- Optional capacity ceiling is an abuse and quality control, configured server-side, never advertised as a product promise. Mirror the `CIRCLE_MEMBER_LIMIT` snapshot idea only if capacity actually becomes a feature.

## Key Decisions

1. **Join policy** — instant join, request + admin approval, or invite-only. Recommendation: instant for `discoverable` groups so discovery stays frictionless, request-based for `unlisted` groups where an organizer is curating. Invite-only already exists as Circle and does not need to be reinvented as a group mode.
2. **Ownership of seeded launch groups** — the shipped groups have no owner today. Either add a nullable `ownerUserId` plus an explicit `isOfficial` flag rendered as an `Official` badge with no admin controls, or reassign seeded groups to real accounts. Recommendation: nullable owner plus `isOfficial`, because reassigning ownership to a real person silently grants that person control of product content.
3. **Rename `Club` to `Group` in the database** — `docs/social.md` currently apologizes for keeping `Club` internally while the product says `Group`. Recommendation: rename now, under the pre-publish data policy, and delete the two-vocabulary split. The alternative (keep `Club`) is cheaper today and permanently inconsistent.
4. **Notice delivery model** — per-recipient `SocialNotification` rows, or a per-member read watermark. Recommendation: watermark, because fanning a notice out to hundreds of members as durable rows is unbounded write amplification for an informational event. See Group Notice below.
5. **Do groups show member activities?** — this is the highest-risk product decision. Recommendation: no. A group shows upcoming runs, a coarse weekly aggregate, and completed group runs. A member's workout is exposed only through the existing connection-visible post rules. Reuse the Circle contribution reconciler instead of building a Group feed that leaks workout facts to strangers.
6. **Name uniqueness** — recommendation: display names are not unique (real clubs collide legitimately); a separate unique slug exists only for share links and is auto-suffixed, not user-typed.
7. **Group run capacity and RSVP** — activity events currently auto-join with no cap. Recommendation: defer capacity and waitlists; keep the existing going/not-going semantics and revisit only if large-group runs actually fill up.
8. **Formal club versus informal crew** — recommendation: one container with independent discovery, verification, joining, roles, schedule, and money axes; never a type enum that drives permissions or forks features. Informal is the default shape and the first thing built; verification, waivers, and dues are earned affordances added later. See Two Shapes, One Model above.

## Group Notice

The broadcast primitive that makes a Group worth having: schedule change, meetup point, weather cancellation, season start.

- Model: `ClubNotice(id, groupId, authorUserId, title?, body, pinned, publishedAt, editedAt, deletedAt?)` with a bounded body (concise, e.g. a few hundred characters) and no attachments in the MVP.
- Authoring is owner/admin only. Members read; members do not post. A notice is not a comment thread and accepts no replies.
- Optional structured reference to a scheduled run or route so a notice can point at the thing it is about.
- Read state: one `ClubNoticeRead(groupId, userId, lastSeenAt/lastSeenNoticeId)` watermark per member, from which unread count is derived. Avoid one read row per member per notice.
- Delivery: do not fan out notices into `SocialNotification` rows. Use the watermark to drive the Groups tab badge, and at most one durable notification per group per notice (dedupe key such as `group-notice:<groupId>:<noticeId>`) for members who have not muted the group.
- Pinning: at most one pinned notice, rendered above upcoming runs in Group detail.
- Editing: allow edit with a visible `edited` marker; do not build an edit history in the MVP.
- Moderation: a notice is user-generated content and inherits every requirement in the App Review Readiness section of `docs/social.md` — pre-publish filtering, report, author delete, admin delete, and block enforcement. Admin delete must be able to remove a notice and notify nobody.

## Group Activity And Group Runs

Two different things share the name; keep them separate.

**Scheduled group runs**, reusing `ActivityEvent`:

- Wire `groupId` through `POST /v1/social/activity-events` and add a group membership/role authorization check mirroring `assertCircleMember`. This closes the existing write gap where `ActivityEvent.clubId` is unreadable-by-write.
- Group detail owns `Up next`, creation, and editing, following the Circle `Plan an activity` pattern: members preselected where appropriate, organizer still reviews time, place, and attendance mode.
- Members see group runs they are eligible for; non-members see them only as a reason to join, never with participant identities.
- Notify members through the existing targeted invitation path plus group-level visibility; reuse `runInvitation` handling instead of inventing a parallel invitation.
- Recurring series is the real unlock for a run club: `ClubRunSeries(groupId, title, weekday, localTime, timeZone, rhythm, locationName, coordinate?, seriesStart, seriesEnd?)` materializing individual `ActivityEvent` instances. Series edits need explicit scope — this instance, this and following, or the whole series — and removing a series must not delete completed history.
- Attendance intent and result reconciliation stay exactly as `docs/social.md` defines them. Never infer physical attendance from GPS.

**Group momentum**, the read-only surface:

- This week's participation count, members active this week, next run, and recently completed group runs.
- Coarse and aggregate by default, matching the Circle stance that progress should feel shared rather than scored.

## Members

- Group detail lists members with role, join date, and at most a coarse activity signal such as `active this week`. Larger groups need the opaque cursor pagination already used for connection lists — the current `take: 50` directory query cannot survive a real club.
- Owner controls: approve or deny join requests, invite by accepted connection or link, promote or demote admins, remove a member, transfer ownership, archive the group.
- Member controls: leave, mute group notifications, report the group or a notice, block another member.
- Leave, removal, and block take effect immediately and revoke all future access. Historical group runs remain visible without exposing the removed member's data to them.
- Blocking overrides every group read and mutation in both directions, exactly as it does for connections.
- Never expose a member's private profile fields, health context, or plan data inside a group.

## Creation And Discovery

- Creation is one scrollable screen, not a wizard: name, optional description, city, focus, join policy, discoverable toggle, and an optional first notice. Never require a first run or a notice to create a group.
- The Groups tab already exists. Add `Create Group` to the persistent Create/Add menu that `docs/social.md` fixes as Plan a run, Add person, Create Circle, and route import.
- Directory: search by name and city, order by nearby and activity, cursor-paginated, with `Official` and community sections so seeded launch groups stay curated.
- Joining shows `Joined`, `Requested`, or `Request pending` rather than a silent state flip, and the action stays idempotent under retry.
- Groups gains its first legitimate badge signal here: pending join requests for owners/admins, plus unread notice via the watermark. That is the reliable personally relevant signal `docs/notifications.md` was waiting for.

## Management And Moderation

- `docs/social.md` App Review Readiness applies in full: objectionable-content filtering before publishing, report flows with named developer response ownership, block coverage across directory, member list, notices, and runs, plus published contact and privacy links.
- Destructive admin actions require confirmation, consistent with the existing confirmations for reporting, blocking, removing a connection, and deleting a post.
- Archiving is the MVP deletion story: history stays readable, no new notices or runs. Hard delete should keep completed `ActivityEvent` rows and strip group attribution, since `ActivityEvent.clubId` is already `SetNull`.
- Group management is a new moderation surface with no operator console. Either scope the MVP to owner-admin self-service with report escalation to the existing support path, or explicitly accept that reports are persisted but unactioned, as `docs/social.md` already does for posts.

## Notifications

- New durable types: `groupJoinRequest`, `groupJoinApproved`, `groupNoticePublished`, `groupOwnershipTransferred`, and the already-anticipated `groupRunInvitation`.
- Extend the type/tier/routing table in `docs/notifications.md` with Groups destinations instead of letting views reinterpret raw type strings.
- Notice bodies never appear in a push payload; route to Group detail and let the client render the stored notice.
- Group mute suppresses optional notices and invitations but never hides membership-critical state.
- Handling a join request deletes its matching durable notification, the way accepted invitations already do.

## Analytics

Measure the loop `directory exposed -> group opened -> join started -> joined or requested -> active -> notice read -> run created -> RSVP -> attended -> second-week participation`.

- Allowed properties are bounded: entry source, join policy, discoverable or unlisted, official or community, viewer role, coarse member-count bucket, request outcome, current-or-future scope for series edits, and normalized failure category.
- Never send group names, slugs, notice titles or bodies, member identities, cities or coordinates, exact counts, or group and user IDs.

## Privacy And Trust

- Group membership is itself sensitive. Recommendation: membership is visible to fellow members and to accepted connections only, and a public profile shows no groups by default. An explicit opt-in "show my groups" can come later.
- Notice audience is members only; unlisted groups are invisible to search and to blocked users.
- Group run meetup coordinates follow the activity-event rule exactly: visible only to joined or invited participants, never to the group at large.
- Reporting and blocking must work from Group detail, a notice, and a member row — not only from the feed.

## Data Model Direction

- Extend the group container: owner, slug, focus, join policy, discoverability, `isOfficial`, lifecycle, optional capacity, updated timestamp.
- Add `ClubJoinRequest`, `ClubNotice`, `ClubNoticeRead`, and later `ClubRunSeries`.
- Extend membership with state, admin promotion timestamp, mute preference, and removal metadata.
- Rename `Club`/`ClubMembership` to `Group`/`GroupMembership` while pre-release, and update `docs/social.md` to stop describing the two-vocabulary split.
- Rollout is destructive and must be documented: `cd backend && npm run db:push -- --accept-data-loss`, plus the Cloud Run schema job in `docs/backend-deploy.md` for the deployed environment.

## API Direction

Authenticated, membership- and role-authorized, block-aware, idempotent, and returning canonical state after mutations.

- `POST /v1/social/groups`, `PATCH /v1/social/groups/:id`, `POST /v1/social/groups/:id/archive`
- `GET /v1/social/groups?query=&city=&cursor=` (replacing the current unpaginated query)
- `GET /v1/social/groups/:id` — member detail with notice, upcoming runs, and member page
- `POST`/`DELETE /v1/social/groups/:id/join-request`, `POST /v1/social/groups/:id/members/:userId`, `POST /v1/social/groups/:id/members/:userId/role`, `POST /v1/social/groups/:id/ownership`
- `GET`/`POST`/`PATCH`/`DELETE /v1/social/groups/:id/notices`, `POST /v1/social/groups/:id/notices/read`
- `POST /v1/social/activity-events` gains `groupId` alongside `sourceCircleId`

## iOS Direction

- Add `GroupStore` and `GroupContracts` under `Domains/Social`; split `SocialGroupsView` into directory, joined list, group detail, notice composer, and management, without adding a root destination.
- Extend the `SocialFeatureTabBar` badge policy for the Groups destination.
- Reuse the existing activity-event creation and invitation flow, connection picker, design system, Dynamic Type, 44-point targets, VoiceOver labels, Reduce Motion, and transient toast feedback.
- Cache only member-authorized group summaries with account scoping, and clear them when authentication changes.
- Localize every new visible string naturally in English, Simplified Chinese, and Spanish.
- Android parity follows the conventions already established in `docs/android-social-parity-prompt.md`.

## Rollout Slices

1. Schema: owner, roles, join policy, verification, notices, watermark; documented destructive rebuild.
2. Create, manage, discover, and join/leave with roles and a paginated directory.
3. Group notices with watermark unread, Groups badge, and moderation hooks.
4. Group runs as single events first, then recurring series.
5. Notification types, analytics funnel, recognition integration, Android parity.
6. Formal-club affordances: organization verification and badge, waiver acknowledgement, public club page, affiliation reference, officer roles, and recurring series at scale. Only after a real club asks.

## MVP Acceptance Criteria

- A runner can create an informal unlisted group from a name alone, with no configuration the creator cannot yet answer, and can later enable discovery, roles, and scheduled runs in place without recreating the group.
- A runner can create a group, edit it, and is its owner; seeded official groups remain usable without granting ownership to a person.
- Ownership transfer works for both shapes, and an informal group whose owner stops participating can be recovered by a remaining member.
- Join policy is enforced server-side for instant, request, and invite paths, and repeated requests stay idempotent.
- Owners and admins can manage members, roles, and ownership transfer; members can leave, mute, report, and block.
- Only owners and admins can publish, edit, pin, or delete a notice; members see unread state via a watermark, and the Groups badge reflects it.
- A group-owned run can be created, discovered by members only, invited to, RSVP'd, recorded against, and reconciled using the existing activity-event lifecycle.
- No group surface exposes a member's workout, route, health, or plan data to non-members.
- Blocked users cannot see or join each other's groups, notices, or runs.
- All new strings are localized, analytics stay within the bounded property allowlist, and backend and iOS build-only verification succeed.

## Open Questions

- Are Groups a directory of many public clubs, or mostly one or two official clubs plus unlisted private ones? The answer changes how much discovery, moderation, and capacity work the MVP needs.
- Does Plainstride store waiver acknowledgement for formal club runs, or explicitly stay out of the liability record?
- Does organization verification attach to a user account or to a standalone organization entity that can own multiple groups?
- When a long-running informal crew outgrows its unlisted state, does it convert in place, and in what order do discovery, roles, and dues get enabled?
- Should membership be publicly discoverable on a profile at all?
- Do notices need read receipts for admins, or is unread count enough?
- Should a group be able to own routes and gear recommendations, or only runs and notices?
- Who owns the report-response obligation for group notices before an operator console exists?

## Deferred

- Group chat, direct messages, and comments on notices.
- Leaderboards, points, streaks, and member rankings.
- Group run capacity limits and waitlists.
- Public group profile pages and SEO/web presence.
- Automated moderation classification and an operator review console.
- Paid or sponsored groups, and organizer tools beyond membership and notices.
- In-app club dues, treasury, or any other money movement.
- Organization verification, affiliation lookup, and public club web pages.
- Waiver capture and liability record keeping.
- A group type picker, a formality enum that gates permissions, or any surface that treats "formal" as an authority claim.
