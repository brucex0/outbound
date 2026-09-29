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

Build native iOS and Android tools for coaches and team managers on the existing Plainstride backend, plus a narrow mobile-web flow for athletes who do not want to install the app. App-less participation is the default pilot path; using the native app is optional.

Included:

- An invite-only, unlisted activity Group for one team.
- Coach-created running or cycling practice events with a start time, duration, and short workout instructions.
- App-less athlete `Going` response and manual `I'm here` / `Finished` practice check-ins through an individual team link.
- A coach roster with aggregate counts and each athlete's explicit check-in state. A guest entry's **Joined** state means the invitation was claimed; it does not verify identity.
- Practice editing and cancellation using existing activity-event behavior.
- Revocable, athlete-specific team invitation links; athletes do not need a Plainstride account or app install for the pilot.
- Coach-managed, pseudonymous roster labels with one revocable participation link per athlete.
- A browser flow for invited athletes to view their team's practices, RSVP, and self-report check-in without an app account or install.
- Localized English, Simplified Chinese, and Spanish strings, accessible states, and allowlisted analytics on both platforms.

Not in V1: live location, routes or GPS, automatic attendance inference, chat or direct messages, photos, leaderboards, streaks, points, custom coach-to-athlete messages, school dashboards, or a coach marketplace. Do not add a separate permanent `Team` entity or a new Group role. Group owner/admin roles manage the team.

## Proposed UX

### Coach-First Entry

The first screen offers three clear routes: **I coach a team**, **Join a team**, and **Track my training**. A team invitation link can also open directly into the join preview, so athletes do not need to find the right button first.

**Join a team** is a recovery/discovery route for someone who has not opened the coach's link yet: show **Open invitation link** and **Paste invitation link**. Do not add a built-in QR scanner in the first cut; phone cameras already open QR URLs, and camera permission would slow this path. A valid invitation opens the mobile browser flow below. The coach's shared link remains the primary join entry.

**I coach a team** is a context shortcut, not a permanent account type or a new identity system:

1. Ask the coach to sign in or create an account using the existing authentication flow. Keep the user's choice through sign-in so they do not have to explain it twice.
2. Skip runner intake, fitness questions, calibration, personal plan setup, and the general Social feed. Do not skip account security, terms, or age/safety requirements that already apply.
3. Show a short **Create your team** form: team name, primary activity (**Run** or **Bike**), and the privacy summary (**Invite-only; only invited team members can see practices**). Apply safe privacy defaults automatically; do not ask the coach to choose visibility settings.
4. After creation, land in the team workspace with two next actions: **Add roster** and **Schedule first practice**. Either can be skipped. Do not require a practice before a coach can invite athletes.

Use the existing Group owner/admin permissions to grant team-management access. The same account can later record personal activities or join another team. Avoid a permanent coach role because a teenager may be both athlete and team organizer.

For returning coaches, sign-in should return directly to their last team workspace. If they manage more than one team, show a compact team picker with **Create another team**. Keep the general training onboarding available from the app for a coach who later wants personal training features.

### Coach Roster Setup

Make the roster useful in under a minute without requiring a spreadsheet or contact import:

1. Offer **Paste roster** with one optional display label per line and a small example such as `Runner 01`. Also provide **Add one athlete** for a late joiner.
2. Recommend aliases or first name plus last initial. Do not require school, age, date of birth, phone, email, guardian contact, or health information. The coach can edit a label or remove an entry later.
3. After save, show each athlete as **Invite ready**, with **Copy link**, **Share**, **Show QR**, and **Reset link** actions. A print-friendly sheet of individual QR codes is useful for in-person team signup, but can follow the minimal share/copy path if it delays the pilot.
4. Tell the coach to send each link only to its intended athlete. Links are individual bearer credentials; a forwarded link can be claimed by someone else until reset. A link becomes bound to its roster entry when accepted and is single-use.
5. Show a compact progress state: invited, joined, and last practice response. Avoid ranking or red/yellow labels that frame missed practices as misconduct.

Do not require an assistant coach flow for the first pilot. Assistant coaches add another permission and support case; first learn whether one coach can operate the team workspace. If this becomes necessary, use existing Group admin invitations and verify that this surfaces only team controls and does not expose members' unrelated activity.

### Team And Roster Surface

Use the existing Group as the durable team container, with a focused team workspace and a role-appropriate first screen:

- **Practices** — upcoming first, then recent practices.
- **Roster** — athlete labels and invite states; coach/admin controls to invite, reset, or remove an athlete.
- **Settings** — team name, privacy, and archive. Per-athlete invitation links live in **Roster**; there is no reusable guest team link.

Coaches see **Roster** after team creation and can switch to **Practices**. Athlete invitees land on **Practices** and never see the management tabs. Use existing Group owner/admin/member permissions; do not create a new `coach` role or separate team table. Defer spreadsheet import until coach interviews show it is essential and clarify which roster data coaches expect to import.

### App-Less Athlete Participation

Recommendation: include a narrow browser participation path in the first pilot. Requiring every athlete to install an app and create an account could prevent a coach from bringing a whole team in. This adds a third surface and a guest-roster contract, so keep the web flow limited to practice coordination.

Coach flow:

- On **Roster**, paste one athlete label per line or add one athlete, then tap **Create invite links**. Generate a distinct link for each roster entry; never make a reusable team-wide guest link.
- Show each row's join state and **Copy link**, **Share**, **Show QR**, and **Reset link** actions. Store no athlete email address or phone number. Coaches distribute links through an existing team channel or show the athlete's QR code in person.
- For a pilot, coach and athlete agree on how the intended athlete receives their link. The product cannot prove that the person opening a forwarded link is that athlete.

Athlete flow:

1. Open the individual invitation on a phone. A preview shows the team name, the assigned alias, what the link allows, and **Accept invite**. Opening the URL alone must not consume it, because messaging apps and security scanners may prefetch links. Do not show the roster or practice list before acceptance.
2. Tap **Accept invite** to claim the single-use link. Do not ask for an account, app install, email, phone, birth date, location, or personal workout data. Then set a secure, revocable browser session.
3. Land on a simple **Your practices** page showing upcoming practice cards and the athlete's own response. Each card has **Going** and **Can't make it**; after the practice starts, an eligible athlete can tap **I'm here**, then **Finish practice**.
4. Show a brief acknowledgement after each save and keep the current state visible on that athlete's page. Provide a clear **This isn't me?** / **Ask coach for a new link** route before acceptance; after acceptance, offer **Leave this team** and tell the coach to reset the invitation if the link was claimed by mistake.
5. Do not show the roster, other athletes' states, or aggregate team attendance in the guest view. Native app account creation and personal activity recording remain optional, separate future paths; do not silently merge a guest identity into an account during this pilot.

This status is self-reported. It is not verified attendance, supervision, or an emergency-safety feature. A forwarded link can be used by someone else until the coach resets it; the roster must make this limitation clear. Coaches can revoke a guest entry immediately. Store a short display label only, keep invite tokens out of logs/analytics, and expire guest sessions after 30 days or when the coach removes the athlete.

Do not build a full PWA or require home-screen installation. The web page needs no push notifications: the coach can share practice updates in their existing team channel and athletes can reopen their link. iOS web push requires a web app added to the home screen plus a user gesture and notification permission, which would reintroduce installation friction. See [WebKit's Web Push overview](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/). School or guardian review still applies to web collection; moving a flow out of the native app does not remove student privacy obligations. See [U.S. Department of Education guidance for online education services](https://studentprivacy.ed.gov/privacy-and-education-technology).

### Coach: Create Team And Invite Athletes

1. Choose **I coach a team**, authenticate, then land on **Create your team**. Do not route through **Social → Groups** or runner onboarding.
2. Enter a team name, select **Run** or **Bike**, review the concise invite-only privacy statement, then tap **Create team**. The server creates the Group with `visibility = unlisted` and `joinPolicy = invite_only` atomically; it must never be briefly public.
3. Land in the team workspace with **Add roster** and **Schedule first practice**. The coach can schedule first or skip it.
4. On **Roster**, paste labels or add athletes one at a time. Confirm the number of invite links before creation. Return a separate seven-day, one-use link per athlete; never use the generic 50-use Group invitation for guest athletes.
5. The roster shows **Invite ready** until the athlete accepts, then **Joined**. Coach can copy/share/show the QR code, reset an unused or claimed link, or remove an athlete. A reset revokes prior guest sessions and issues a replacement link.
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

1. Open their own link from a coach's message or QR code. A link preview crawler sees only a generic landing response; only the athlete's explicit **Accept invite** action consumes the link.
2. Review the team name, coach-assigned label, and invitation purpose, then tap **Accept invite**. This app-less path does not require sign-in or an app install. The server binds the single-use invitation to a revocable guest session.
3. Land on **Your practices**. See only the athlete's upcoming practice details and own RSVP/check-in state. Tap **Going** or **Can't make it**; update the RSVP later if plans change.
4. From 60 minutes before the scheduled start until two hours after it ends, a going athlete may tap **I'm here**, followed by **Finish practice**. Check-in is always a deliberate self-report.
5. After marking finished, show a small confirmation. No synthetic activity is created, and no GPS permission is requested. If the link is wrong or shared with the wrong person, provide a path to contact the coach and reset it.

### Coach: Take Attendance

The practice detail shows roster statuses to owners/admins:

- **Going** — athletes who RSVP'd but have not checked in.
- **Here** — athletes who tapped `I'm here`.
- **Finished** — athletes who tapped `Finish practice`.
- **Can't make it** and **No response** — collapsed secondary sections.

Show counts in each section. Only Group owner/admin can see individual roster labels and states. App-less athletes see only their own state; do not show them aggregate attendance. Coaches can edit/cancel a scheduled practice; they cannot mark an athlete present or finished for them.

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

For optional account-backed assistant coaches, existing `POST /v1/social/groups/:groupId/invite-links` can accept:

```json
{ "expiresInDays": 7, "maxUses": 50 }
```

This generic Group invitation is for account membership or a later assistant-coach slice; it is not the athlete join path and should not be created during initial team setup. The response returns `{ "id", "token", "url", "expiresAt", "maxUses" }`; store only the token digest. Existing revoke and consume routes remain authoritative. One link is revocable by owner/admin. Expired, revoked, exhausted, and invalid links return the same not-found style response.

Add a separate browser route such as `/team/join#<token>`; keeping the opaque token in the URL fragment avoids sending it to the web server in the initial page request or as a referrer. The page extracts it and submits it in the body of the explicit accept request. Keep `/invite/group/:token` and its existing account-backed Group invitation behavior unchanged. The new page shows only the team name, the coach-assigned athlete label, and **Accept invite**; after acceptance it shows that guest's practice list and own controls. It never shows team roster names or other athletes' states. The initial page response must not reveal whether a token is valid.

Add `POST /v1/guest/team-invites/preview` with `{ "token": "..." }` so the browser can show the team name, assigned label, and invite expiry without consuming the link. It returns no practice list or roster information. The token remains in the fragment until accepted and is sent only in the POST body; redact request bodies from logs and analytics. The preview is optional from a product standpoint: if this complicates the pilot, show a generic team-invitation explanation and reveal the team/label only after acceptance.

Add a `GroupGuestRosterEntry` model containing `id`, `groupId`, `displayLabel`, a unique invite-token digest, invite expiry, accepted timestamp, guest-session-token digest/expiry, revoked timestamp, and created/updated timestamps. It is not a `GroupMember`, cannot access Social or personal activity data, and can be read/managed only by the team's owner/admin. **Joined** means the link was claimed, not that the intended athlete's identity was verified. Add `ActivityEventGuestParticipant` keyed by `(activityEventId, guestRosterEntryId)` with nullable `rsvpState` (`going` or `not_going`) and nullable `practiceCheckInState` (`here` or `finished`). No participation row means no response yet.

Coach roster creation:

```http
POST /v1/social/groups/:groupId/guest-roster
```

```json
{
  "athletes": [{ "displayLabel": "Alex R." }, { "displayLabel": "Runner 02" }],
  "idempotencyKey": "client-generated-key"
}
```

Allow 1–100 labels, each 1–40 characters. Owner/admin only. The response returns `{ "entries": [{ "id", "displayLabel", "inviteUrl", "expiresAt" }] }`. Each opaque 256-bit invite token is returned once, expires in seven days, and can be revoked or reset individually. Store only its digest. The browser consumes it by explicit POST; link preview crawlers must not activate it.

Guest browser API:

- `POST /v1/guest/team-invites/accept` accepts `{ "token": "..." }`, atomically claims the invite, sets a Secure, HttpOnly, SameSite guest-session cookie scoped to this Group entry, and returns the athlete label and upcoming practices. The page explains that the link should be used only by its intended recipient before acceptance. If the browser loses its guest session, recovery goes through the coach resetting the link; the consumed token is not a reusable login credential.
- `GET /v1/guest/team` returns only this guest's team name, label, upcoming practice cards, and their own RSVP/check-in states. Do not expose roster entries through page source, cached APIs, or aggregate endpoints.
- `PUT /v1/guest/activity-events/:eventId/rsvp` accepts `{ "state": "going" | "not_going" }`.
- `PUT /v1/guest/activity-events/:eventId/check-in` accepts `{ "state": "here" | "finished" }` within the same time window as the account-backed check-in.
- `DELETE /v1/social/groups/:groupId/guest-roster/:entryId` revokes the entry and all guest sessions immediately. A manager-only reset action issues a new one-use link.

All guest routes validate that the roster entry and event belong to the same active unlisted Group and that the event remains within its allowed lifecycle. Guest sessions expire after 30 days or immediately on revocation/removal. Protect cookie-authenticated mutations against cross-site request forgery, use same-site hosting for the browser and API where possible, and never put raw invite/session tokens in analytics, URLs sent to the server, or logs.

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

Only Group owner/admin can create a community Group practice. The server rejects non-null location fields for this pilot surface. A practice attached to an unlisted Group gets `visibility = group` and is visible only to active Group members, its account participants, authorized guest-roster participants through guest routes, or directly invited people; it must not inherit the current community-event default of public visibility. The event response never includes routes, athlete activity facts, health data, or precise location.

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

Response: `{ "counts": { "going", "here", "finished", "notCheckedIn", "notGoing", "noResponse" }, "participants": [{ "entryId", "displayLabel", "rsvpState", "practiceCheckInState", "kind": "account" | "guest" }] }`. Here, finished, and notCheckedIn are mutually exclusive subsets of going. Only active Group owners/admins can call this route. Every other viewer receives 403/404 without roster data. Coaches cannot mutate a participant's state. The server sets `visibility = group` for events attached to unlisted Groups and permits reads only to active Group members, account participants, active guest participants through guest routes, or direct invitees. Public event discovery must never return these practices.

## Data And Safety Rules

- Team Groups are community-policy Groups, unlisted and invite-only. They never expose a member's unrelated activities.
- Do not request, collect, store, transmit, or display athlete GPS as part of the practice feature. The existing activity recorder's independent permissions and behavior are unchanged.
- Manual practice check-in is separate from an activity recording and from the event's `outcome`; never turn it into a synthetic workout or infer attendance from GPS.
- Only the athlete changes their practice state. Coaches may view the roster and schedule/cancel events but cannot impersonate check-ins.
- Limit native access to active Group members; owner/admin-only individual roster projection; guest access through a scoped session to that athlete's own status only; share-safe aggregates for account members.
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
2. Welcome screen offers **I coach a team**, **Join a team**, and **Track my training**. Coach setup authenticates, skips runner-specific setup, and opens team creation.
3. Team creation asks only name, Run/Bike, and a short privacy statement; afterward coaches can add a roster or schedule the first practice in either order.
4. Athlete join uses an individual, seven-day, one-use link, accepts in a browser without an account or install, and lands on **Your practices**. QR sharing is desirable for in-person signup, but optional for the first cut.
5. Coach roster uses aliases or minimal labels. A claimed invite shows **Joined**, which does not verify athlete identity. Athletes see only their own state; coaches see roster labels, states, and counts.
6. Use the exact practice fields, status labels, check-in window, and API proposal above.
7. Build iOS and Android together against the same backend contract; keep the athlete guest web flow narrow.
8. Keep live location and coach-sent live cues out of this first pilot.
