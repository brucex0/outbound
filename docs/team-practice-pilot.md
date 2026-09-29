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

Build the same coach and athlete flow for iOS and Android on the existing Plainstride backend.

Included:

- An invite-only, unlisted activity Group for one team.
- Coach-created running or cycling practice events with a start time, duration, and short workout instructions.
- Athlete `Going` response and manual `I'm here` / `Finished` practice check-ins.
- A coach roster with aggregate counts and each athlete's explicit check-in state.
- Practice editing and cancellation using existing activity-event behavior.
- Revocable team invitation links and existing sign-in/deep-link handling.
- Localized English, Simplified Chinese, and Spanish strings, accessible states, and allowlisted analytics on both platforms.

Not in V1: live location, routes or GPS, automatic attendance inference, chat or direct messages, photos, leaderboards, streaks, points, custom coach-to-athlete messages, school dashboards, or a coach marketplace. Do not add a separate permanent `Team` entity or a new Group role. Group owner/admin roles manage the team.

## Proposed UX

### Coach: Create Team

1. Open **Social → Groups → Create Group → Organize activities**.
2. Enter team name and choose activity interest: **Running** or **Cycling**.
3. Choose **Invite only**. This creates a community Group with `visibility = unlisted` and `joinPolicy = invite_only` atomically; it must never be briefly public.
4. Create an invitation link with a seven-day expiry and a 50-use limit. Show **Copy invite link** and **Revoke link**. The coach shares it through their existing team channel.
5. Group detail opens to **Upcoming practices**, then a clear **Schedule practice** action. Existing notices remain available but are not required to create a practice.

### Coach: Schedule Practice

The form contains:

- **Practice name** (default: `Team practice`; 80 characters maximum).
- **Activity** (`Run` or `Bike`, preselected from the Group interest).
- **Date and start time** in the coach's local time zone.
- **Duration** (default 60 minutes; 15 minutes to 4 hours).
- **Workout instructions** (optional, up to 240 characters; use the existing event note field).
- Primary action: **Schedule practice**.

Do not show a map, route picker, exact meetup coordinates, or live-location setting. After saving, show the practice detail and a transient success toast. The detail shows date/time, duration, instructions, and `Going` count. The Group detail owns **Copy team invite link**.

### Athlete: Join Team And Practice

1. Open the invitation link, review the Group name, description, and invite-only status, sign in if needed, then tap **Join team**.
2. In Group detail, see upcoming practice cards with date/time and coach instructions.
3. Open a practice and tap **Going** or **Can't make it**. `Going` uses the existing event RSVP; `Can't make it` removes the RSVP without reporting attendance.
4. From 60 minutes before the scheduled start until the event closes, a going athlete sees **I'm here**. After checking in, it changes to **Finish practice**. Check-in is always a deliberate athlete action.
5. After marking finished, the athlete sees a quiet confirmation. No synthetic activity is created and no GPS permission is requested.

### Coach: Take Attendance

The practice detail shows roster sections:

- **Going** — athletes who RSVP'd but have not checked in.
- **Here** — athletes who tapped `I'm here`.
- **Finished** — athletes who tapped `Finish practice`.

Show counts in each section. Only Group owner/admin can see individual roster names and states. Athletes see their own state and aggregate counts, not other athletes' check-in states. Coaches can edit/cancel a scheduled practice; they cannot mark an athlete present or finished for them.

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
  "idempotencyKey": "client-generated-key"
}
```

For `template = activities`, validate and store visibility/join policy in the same transaction as creation. Defaults remain unchanged for other callers. Do not create a public Group and patch it afterward.

Existing `POST /v1/social/groups/:groupId/invite-links` gains an optional body:

```json
{ "expiresInDays": 7, "maxUses": 50 }
```

The response returns `{ "id", "token", "url", "expiresAt", "maxUses" }`; store only the token digest. Existing revoke and consume routes remain authoritative. One link is revocable by owner/admin. Expired, revoked, exhausted, and invalid links return the same not-found style response.

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

Only Group owner/admin can create a community Group practice. The server rejects non-null location fields for this pilot surface. A practice attached to an unlisted Group gets `visibility = group` and is visible only to active Group members, its participants, or directly invited people; it must not inherit the current community-event default of public visibility. The event response never includes routes, athlete activity facts, health data, or precise location.

### RSVP And Check-In

Reuse the existing `POST /v1/social/activity-events/:eventId/rsvp` with `{ "attendanceMode": "in_person" }` and existing delete-RSVP behavior.

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
    "notCheckedIn": 4
  },
  "currentUserPracticeCheckIn": "here"
}
```

`going` is the total accepted RSVP count; `here`, `finished`, and `notCheckedIn` are mutually exclusive states whose sum equals `going`. Only active Group members and direct invitees receive this aggregate and their own state. The event's ordinary participant payload must not leak names or individual check-in states to athletes in a community Group. No exact check-in timestamp is returned.

Add a manager-only roster route:

```http
GET /v1/social/activity-events/:eventId/practice-roster
```

Response: `{ "counts": { "going", "here", "finished", "notCheckedIn" }, "participants": [{ "user": compactPerson, "state": "not_checked_in" | "here" | "finished" }] }`. Only active Group owners/admins can call it. Every other viewer receives 403/404 without roster data. Coaches cannot mutate a participant's state. The server sets `visibility = group` for events attached to unlisted Groups and permits reads only to active Group members, participants, or direct invitees. Public event discovery must never return these practices.

## Data And Safety Rules

- Team Groups are community-policy Groups, unlisted and invite-only. They never expose a member's unrelated activities.
- Do not request, collect, store, transmit, or display athlete GPS as part of the practice feature. The existing activity recorder's independent permissions and behavior are unchanged.
- Manual practice check-in is separate from an activity recording and from the event's `outcome`; never turn it into a synthetic workout or infer attendance from GPS.
- Only the athlete changes their practice state. Coaches may view the roster and schedule/cancel events but cannot impersonate check-ins.
- Limit access to active Group members; owner/admin-only individual roster projection; athlete-only own status; share-safe aggregates for members.
- Apply block/removal and Group lifecycle rules on every read and mutation. Revoking the team link must stop future joins immediately.
- Keep invite tokens, Group/event/user IDs, athlete names, check-in states, workout instructions, and school/team names out of analytics and logs.
- Before a real teen pilot, obtain school and guardian review for the selected pilot context, confirm age handling and consent, publish support/contact and deletion paths, and define who responds to reports. COPPA and school privacy obligations depend on age, data, and deployment context; this spec does not replace legal review.

## Analytics And Pilot Scorecard

Add typed, platform-parity events using only the existing analytics allowlist:

- `team_practice_group_created`
- `team_practice_invite_link_created`
- `team_practice_invite_link_consumed`
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
2. Coach view includes individual check-in names/states; athletes see only their own state plus aggregate counts.
3. Use the exact practice fields, status labels, check-in window, and API proposal above.
4. Build iOS and Android together against the same backend contract.
5. Keep live location and coach-sent live cues out of this first pilot.
