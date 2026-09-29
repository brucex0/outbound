# Team Practice Pilot

Open this when evaluating or implementing the first coach-led team workflow for high school cross-country, mountain biking, or another youth endurance team. This is a proposed pilot contract for owner review; it is not approval to start implementation.

## Product Hypothesis

Coaches may bring a team onto Plainstride if it makes practice coordination easier. Athletes may return because practice feels shared and they receive encouragement from their coach and teammates. The first test should establish repeated team use before testing live location or live coaching.

This extends the teen-team wedge in `docs/product-strategy.md`. The product promise is to build love, motivation, and consistency around moving. Do not position the pilot as a Strava replacement or as a school administration system.

## What We Need To Learn

1. Can a coach create and reuse a practice with less coordination effort than their current tools?
2. Will athletes join the team and check in across multiple practices?
3. Do coaches want live athlete visibility enough to accept its privacy, consent, and operational cost?
4. Does team use bring in families and friends, or does the team remain an isolated feature?

Interview coaches about their last practices and recruit at least one coach to run a real pilot before implementation. Treat scheduling and completing several real practices as stronger evidence than stated interest.

## V1 Scope

Build coach and athlete flows in the iOS and Android apps using authenticated Group membership and the existing Plainstride backend. Do not build guest accounts or an athlete web app in this pilot. Keep app-less participation as the next fallback if required app install/account creation blocks team adoption.

Included:

- An invite-only, unlisted activity Group for one team.
- Coach-created running or cycling practice events with a start time, duration, and short workout instructions.
- Athlete `Going` / `Can't make it` responses and manual `I'm here` / `Finished` practice check-ins in the native app.
- An account-backed coach roster with each active athlete's RSVP and check-in state.
- Practice editing and cancellation using existing activity-event behavior.
- Revocable, athlete-specific team invitation links that open in Plainstride and require sign-in or account creation before joining.
- Coach-managed optional roster labels for pending invites; once accepted, the roster is tied to the athlete's Plainstride account.
- App-less participation remains a documented fallback path, not a V1 deliverable.
- Localized English, Simplified Chinese, and Spanish strings, accessible states, and allowlisted analytics on both platforms.

Not in V1: live location, routes or GPS, automatic attendance inference, chat or direct messages, photos, leaderboards, streaks, points, custom coach-to-athlete messages, school dashboards, or a coach marketplace. Do not add a separate permanent `Team` entity or a new Group role. Group owner/admin roles manage the team.

## Proposed UX

### Coach-First Entry

The first screen offers three clear routes: **I coach a team**, **Join a team**, and **Track my training**. A team invitation link can also open directly into the join preview, so athletes do not need to find the right button first.

**Join a team** is a recovery route for someone who has not opened the coach's link yet: show **Open invitation link** and **Paste invitation link**. Do not add a built-in QR scanner in the first cut; phone cameras already open QR URLs, and camera permission would slow this path. A valid invitation opens the in-app Group preview. The coach's shared link remains the primary join entry.

**I coach a team** is a context shortcut, not a permanent account type or a new identity system:

1. Ask the coach to sign in or create an account using the existing authentication flow. Keep the user's choice through sign-in so they do not have to explain it twice.
2. Skip runner intake, fitness questions, calibration, personal plan setup, and the general Social feed. Do not skip account security, terms, or age/safety requirements that already apply.
3. Show a short **Create your team** form: team name, primary activity (**Run** or **Bike**), and the privacy summary (**Invite-only; only invited team members can see practices**). Apply safe privacy defaults automatically; do not ask the coach to choose visibility settings.
4. After creation, land in the team workspace with two next actions: **Add roster** and **Schedule first practice**. Either can be skipped. Do not require a practice before a coach can invite athletes.

Use the existing Group owner/admin permissions to grant team-management access. The same account can later record personal activities or join another team. Avoid a permanent coach role because a teenager may be both athlete and team organizer.

For returning coaches, sign-in should return directly to their last team workspace. If they manage more than one team, show a compact team picker with **Create another team**. Keep the general training onboarding available from the app for a coach who later wants personal training features.

### Coach Roster Setup

Make the roster useful in under a minute without requiring a spreadsheet or contact import:

1. Offer **Add athletes** with one optional roster label per line (for example `Runner 01`) and **Add one athlete** for late joiners. Do not import contacts or require school, age, date of birth, phone, email, guardian contact, or health information.
2. Create one seven-day, one-use invitation per roster label. The coach can use the native share sheet, copy a link, or show a QR code. Do not make a reusable team-wide athlete link.
3. Label each row **Invite ready**, then **Joined** after an authenticated account claims that invitation. Until accepted, the coach sees only the label and invite state; after acceptance, the roster shows the member's account profile and team role.
4. Explain that links are bearer credentials: anyone who receives one can claim it with their account. A label helps the coach route links but does not verify who accepted. Coaches can revoke/reset before or after claim and remove an active member through normal Group management.
5. Show a compact progress state: invited, joined, and each member's last practice response. Avoid ranking or red/yellow labels that frame missed practices as misconduct.

Do not require an assistant coach flow for the first pilot. Assistant coaches add another permission and support case; first learn whether one coach can operate the team workspace. If this becomes necessary, use existing Group admin invitations and verify that this surfaces only team controls and does not expose members' unrelated activity.

### Team And Roster Surface

Use the existing Group as the durable team container, with a focused team workspace and a role-appropriate first screen:

- **Practices** — upcoming first, then recent practices.
- **Roster** — athlete labels and invite states; coach/admin controls to invite, reset, or remove an athlete.
- **Settings** — team name, privacy, and archive. Per-athlete invitation links live in **Roster**; do not expose a reusable public join code.

Coaches see **Roster** after team creation and can switch to **Practices**. Athletes land on **Practices** after joining and never see the management tabs. Use existing Group owner/admin/member permissions; do not create a new `coach` role or separate team table. Defer spreadsheet import until coach interviews show it is essential and clarify which roster data coaches expect to import.

### App-Less Fallback (Deferred)

If coaches report that install, sign-in, or account creation is preventing roster-wide participation, test an app-less browser join/check-in path next. Keep it scoped to practice coordination and add a separate guest identity/session model; never let an unverified link holder access the full Group or other athletes' states. The app-only pilot should measure invitation opened → app opened/installed → account ready → team joined → first practice response so we can tell whether this friction is real before taking on the extra web surface.

### Coach: Create Team And Invite Athletes

1. Choose **I coach a team**, authenticate, then land on **Create your team**. Do not route through general Social or runner onboarding.
2. Enter a team name, select **Run** or **Bike**, review the concise invite-only privacy statement, then tap **Create team**. The server creates the Group with `visibility = unlisted` and `joinPolicy = invite_only` atomically; it must never be briefly public.
3. Land in the team workspace with **Add roster** and **Schedule first practice**. The coach can schedule first or skip it.
4. On **Roster**, paste labels or add athletes one at a time. Confirm how many links will be generated. Return a separate seven-day, one-use link per athlete; never use the generic reusable Group invitation link for the team roster.
5. The roster shows **Invite ready** until an authenticated athlete accepts, then **Joined**. Coach can copy/share/show the QR code, revoke or reset an invitation, or remove an active member. If a link is reset after acceptance, the athlete remains a member unless the coach separately removes them.
6. Returning coaches open their last team directly. Coaches with multiple teams get a team picker and can create another team.

### Coach: Schedule Practice

The form contains:

- **Practice name** (default: `Team practice`; 80 characters maximum).
- **Activity** (`Run` or `Bike`, preselected from the Group interest).
- **Date and start time** in the coach's local time zone.
- **Duration** (default 60 minutes; 15 minutes to 4 hours).
- **Workout instructions** (optional, up to 240 characters; use the existing event note field).
- Primary action: **Schedule practice**.

Do not show a map, route picker, exact meetup coordinates, or live-location setting. After saving, show the practice detail and a transient success toast. The detail shows date/time, duration, instructions, and `Going` count. Per-athlete invitation links remain in **Roster**.

### Athlete: Join Team And Practice

1. Open their individual coach link. If the app is installed, the existing Group invite link opens its in-app preview. If not installed, the web invitation page offers install/open-app guidance and tells the athlete to reopen the same link after sign-in; this is the expected app-required pilot path.
2. Sign in or create a Plainstride account, then review the team name and the coach-assigned roster label. Tap **Join team** to claim the one-use link. The membership is bound to the authenticated account; the link itself still cannot prove that the intended athlete accepted it.
3. Land on the team's **Practices** tab. See upcoming practice cards and the athlete's own RSVP/check-in state. Tap **Going** or **Can't make it**; update the response later if plans change.
4. From 60 minutes before the scheduled start until two hours after it ends, a going athlete may tap **I'm here**, followed by **Finish practice**. Check-in is always a deliberate self-report.
5. After marking finished, show a small confirmation. No synthetic activity is created, and no GPS permission is requested. If the link was claimed by the wrong account, the coach revokes that membership and sends a replacement link.

### Coach: Take Attendance

The practice detail shows roster statuses to owners/admins:

- **Going** — athletes who RSVP'd but have not checked in.
- **Here** — athletes who tapped `I'm here`.
- **Finished** — athletes who tapped `Finish practice`.
- **Can't make it** and **No response** — collapsed secondary sections.

Show counts in each section. Only Group owner/admin can see individual roster labels and states. Athletes see their own state plus aggregate counts, not other athletes' individual states. Attendance counts include `member` athletes only, not owner/admin coaches. Coaches can edit/cancel a scheduled practice; they cannot mark an athlete present or finished for them.

## Proposed API Contract

All routes use the existing authenticated `/v1` API and canonical server responses. Existing Group and activity-event routes are reused. The additions below are proposed and need owner confirmation before code.

### Create A Safe Team Group

Extend `POST /v1/social/groups` to accept optional fields:

```json
{
  "template": "activities",
  "name": "North Ridge XC",
  "activityInterests": ["running"],
  "visibility": "unlisted",
  "joinPolicy": "invite_only",
  "noticesEnabled": false,
  "scheduledActivitiesEnabled": true,
  "memberActivityCreation": false,
  "idempotencyKey": "client-generated-key"
}
```

For `template = activities`, validate and store visibility, join policy, and team capability flags in the same transaction as creation. Defaults remain unchanged for other callers. Do not create a public Group and patch it afterward.

Extend `POST /v1/social/groups/:groupId/invite-links` with optional creation rules. For a team, the coach creates one one-use link per roster label, with a seven-day expiry:

```json
{ "displayLabel": "Runner 01", "expiresInDays": 7, "maxUses": 1 }
```

Extend the existing route to accept the body above and return one link as `{ "id", "token", "url", "expiresAt", "maxUses" }`; add a batch team-roster route to reduce coach setup time:

```http
POST /v1/social/groups/:groupId/team-invites
```

```json
{
  "athletes": [{ "displayLabel": "Runner 01" }, { "displayLabel": "Runner 02" }],
  "expiresInDays": 7,
  "idempotencyKey": "client-generated-key"
}
```

Owner/admin only; allow 1–100 labels, each 1–40 characters. Return `{ "invites": [{ "id", "displayLabel", "url", "expiresAt", "status" }] }`, with raw tokens returned once. Extend `GroupInviteLink` with an optional display label and a `claimedByUserId` set atomically when the authenticated invite is consumed; do not create a separate roster identity table. Store only token digests. Each link is revocable/resettable by owner/admin. A link binds the label to the first account that claims it; this does not prove the account belongs to the intended athlete. Enforce `maxUses = 1` in the same transaction that creates membership and records the claimant, so simultaneous accepts cannot consume the same invite twice.

Add manager-only team roster retrieval:

```http
GET /v1/social/groups/:groupId/team-roster
```

Response includes active account members with Group role, plus pending/claimed invitation labels and status. Only owner/admin can view this roster projection. On consume through the existing authenticated `POST /invite/group/:token/consume`, bind the claimed account to its invite row and make the account a normal `GroupMember`. Existing `/invite/group/:token` preview, app-link handling, and authentication requirements remain the entry path; the athlete must sign in or create an account before **Join team** succeeds.

Suggested response shape:

```json
{
  "members": [{ "user": "compactPerson", "role": "member", "joinedAt": "..." }],
  "invites": [{ "id": "...", "displayLabel": "Runner 01", "status": "invite_ready", "claimedUser": null, "expiresAt": "..." }]
}
```

### Create A Practice

Reuse `POST /v1/social/activity-events` with the existing fields and the following constraints for a team practice:

```json
{
  "title": "Team practice",
  "activityType": "running",
  "startsAt": "2026-10-05T22:30:00.000Z",
  "durationMinutes": 60,
  "note": "Easy warm-up, then 6 x 2 minutes at a controlled effort.",
  "groupId": "<group-id>",
  "participationMode": "in_person",
  "locationName": null,
  "latitude": null,
  "longitude": null
}
```

Only Group owner/admin can create a community Group practice. The server rejects non-null location fields for this pilot surface. A practice attached to an unlisted Group gets `visibility = group` and is visible only to active Group members, account participants, or directly invited people; it must not inherit the current community-event default of public visibility. The event response never includes routes, athlete activity facts, health data, or precise location.

### RSVP And Check-In

Add an idempotent team practice response endpoint so `Can't make it` is distinct from leaving an event:

```http
PUT /v1/social/activity-events/:eventId/practice-response
```

```json
{ "state": "going" }
```

`state` is `going` or `not_going`. The signed-in athlete must be an active member of the event's Group. Store `not_going` on the participant row; no row means no response. Existing generic activity-event RSVP behavior remains unchanged outside this team flow.

Add an idempotent participant-owned endpoint and a nullable `practiceCheckInState` field on `ActivityEventParticipant` (`here` or `finished`; null means not checked in):

```http
PUT /v1/social/activity-events/:eventId/practice-check-in
```

Request:

```json
{ "state": "here" }
```

Allowed states are `here` and `finished`. The authenticated user must have a `going` participant row for this in-person Group event. The server accepts check-ins from 60 minutes before `startsAt` through two hours after `endsAt`; repeated requests are safe. A finished state cannot be changed back to here. No client can check in another athlete.

### Practice Detail And Roster

Extend `GET /v1/social/activity-events/:eventId` with:

```json
{
  "practiceCheckInSummary": {
    "going": 18,
    "here": 5,
    "finished": 9,
    "notCheckedIn": 4,
    "notGoing": 3,
    "noResponse": 2
  },
  "currentUserPracticeResponse": "going",
  "currentUserPracticeCheckIn": "here"
}
```

`going` is the accepted affirmative RSVP count; `here`, `finished`, and `notCheckedIn` are mutually exclusive states whose sum equals `going`. Add `notGoing` and `noResponse` counts for the other active Group members. Ordinary athletes receive aggregate counts and their own state only; the event's ordinary participant payload must not leak names or individual check-in states to athletes in a community Group. No exact check-in timestamp is returned.

Add a manager-only roster route:

```http
GET /v1/social/activity-events/:eventId/practice-roster
```

Response: `{ "counts": { "going", "here", "finished", "notCheckedIn", "notGoing", "noResponse" }, "participants": [{ "user": compactPerson, "rsvpState", "practiceCheckInState" }] }`. Counts and participant rows cover active `member` athletes, not owner/admin coaches; `here`, `finished`, and `notCheckedIn` are mutually exclusive subsets of `going`. Only active Group owners/admins can call this route. Every other viewer receives 403/404 without roster data. Coaches cannot mutate a participant's state. The server sets `visibility = group` for events attached to unlisted Groups and permits reads only to active Group members, account participants, or direct invitees. Public event discovery must never return these practices.

## Data And Safety Rules

- Team Groups are community-policy Groups, unlisted and invite-only. They never expose a member's unrelated activities.
- Do not request, collect, store, transmit, or display athlete GPS as part of the practice feature. The existing activity recorder's independent permissions and behavior are unchanged.
- Manual practice check-in is separate from an activity recording and from the event's `outcome`; never turn it into a synthetic workout or infer attendance from GPS.
- Only the athlete changes their practice state. Coaches may view the roster and schedule/cancel events but cannot impersonate check-ins.
- Limit native access to active Group members; owner/admin-only individual roster projection; athlete-only access to their own status plus share-safe aggregates.
- Apply block/removal and Group lifecycle rules on every read and mutation. Revoking an invite link stops future joins immediately; removing an accepted athlete revokes Group and practice access.
- Keep invite tokens, Group/event/user IDs, athlete names, check-in states, workout instructions, and school/team names out of analytics and logs.
- Before a real teen pilot, obtain school and guardian review for the selected pilot context, confirm age handling and consent, publish support/contact and deletion paths, and define who responds to reports. COPPA and school privacy obligations depend on age, data, and deployment context; this spec does not replace legal review.

## Analytics And Pilot Scorecard

Add typed, platform-parity events using only the existing analytics allowlist:

- `team_practice_group_created`
- `team_practice_invite_link_created`
- `team_practice_invite_opened`
- `team_practice_joined`
- `team_practice_auth_completed`
- `team_practice_scheduled`
- `team_practice_rsvp_changed`
- `team_practice_check_in_changed`
- `team_practice_cancelled`

Allowed properties: entry point, activity type, coarse member-count bucket, role, state, and normalized outcome/failure category. Do not send IDs, names, precise times, text, tokens, location, or school/team identity.

Primary measures:

- Coaches who schedule a second and third practice.
- Athletes who RSVP and manually check in across multiple practices.
- Coach-reported coordination time or effort compared with their current process.
- Athletes who return to the team flow the following week.

Guardrails: invite-link misuse, athlete confusion or pressure, removals, blocks, reports, privacy concerns, and coach roster access errors. Agree on numeric decision thresholds with the pilot coach before launch; do not manufacture a success threshold from a small sample after seeing results.

## Delivery Sequence After Approval

1. Backend contract and authorization, with a disposable schema update only if required.
2. iOS coach/athlete journey, using the shared API and localization catalog.
3. Android parity journey using the same states, API, and analytics names.
4. Build-only verification on backend, iOS, and Android; do not run tests unless requested.
5. Recruit and onboard the pilot coach, confirm school/guardian review, run several practices, and review the scorecard before considering live coaching.

Per repository commit policy, backend, iOS, and Android changes will be committed separately with `[BE]`, `[iOS]`, and `[Droid]` prefixes.

## Owner Review Required Before Coding

Confirm or edit:

1. Use an **unlisted, invite-only community Group** for a school team.
2. Welcome screen offers **I coach a team**, **Join a team**, and **Track my training**. Coach setup authenticates, skips runner-specific setup, and opens team creation.
3. Team creation asks only name, Run/Bike, and a short privacy statement; afterward coaches can add a roster or schedule the first practice in either order.
4. Athlete join uses an individual, seven-day, one-use link, requires sign-in or account creation, and lands in the app on **Practices**. The same URL can guide athletes through install and back into the invite if the app is missing.
5. Coach roster uses optional labels for pending links and account profiles after join. A claimed invite still does not verify that the account belongs to the intended athlete. Athletes see only their own state plus aggregates; coaches see roster labels, names, states, and counts.
6. Use the exact practice fields, status labels, check-in window, and API proposal above.
7. Build iOS and Android together against the same authenticated backend contract. Keep app-less browser participation as a follow-on if invite-to-join data shows app friction is blocking adoption.
8. Keep live location and coach-sent live cues out of this first pilot.
