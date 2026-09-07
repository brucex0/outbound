# Safety And Live Tracking

Open this when designing or implementing trusted-contact live tracking, route privacy, or safety controls.

## Product Gap

Strava Beacon, Runkeeper Go, MapMyRun, and AllTrails all make live tracking or location sharing feel like a serious trust feature. Outbound has local live activity UI and background GPS, but it does not yet let a runner share an active session with trusted people.

This is not just social sharing. It is safety, consent, privacy, and reliability.

## Product Position

Outbound should ship live tracking as a trust feature before trying to make it playful.

Promise:

- "Invite Xia to cheer me on."

Do not lead with public maps, follower broadcasts, or social presence. Those can come later after privacy and identity are solid.

## User Experience

### In-App Cheer Invitation

Entry points:

- pre-start safety row on the activity start page
- live session safety control in the camera/map HUD
- Settings area for trusted contacts and default behavior

Flow:

1. Runner opens `Invite someone to cheer me on`.
2. Runner selects one or more accepted Plainstride connections.
3. The invitees receive an in-app notification and open the live session from Social.
4. They see precise location, route, elapsed time, distance, pace, and heart rate.
5. They hold the microphone control to record an original voice cheer of up to 15 seconds.
6. The recording plays directly through the runner's existing guide-audio path between guide cues.
7. Sharing and new voice cheers end when the activity finishes or expires.

Default behavior:

- off by default
- app account and accepted connection required
- do not expose photos, exact home address history, or past activities
- show the runner an obvious active-sharing indicator during the whole session

### Separate Safety Escalation

Outside the cheering experience:

- overdue check-in prompt
- "I am safe" quick message
- crash/fall or long-stationary detection experiments
- configurable route privacy zones around home/work

Do not imply emergency-service coverage unless the product actually integrates with emergency services.

## Privacy Rules

- Live tracking requires explicit per-session consent.
- Every live share has an expiry.
- Revocation must work immediately from the runner's device.
- Recipients should see only the active session, not the runner's profile or full activity history.
- Server logs should avoid storing high-resolution location longer than needed for the active share.
- The app should support route privacy zones before broad social route sharing.

## Backend Shape

Suggested domain: `safety`.

Core tables:

- `SafetyShareSession`
  - `id`
  - `userId`
  - `activityId` nullable until the workout is saved
  - `startedAt`
  - `expiresAt`
  - `endedAt`
  - `status`: active, ended, expired, revoked
  - `lastLocationAt`
  - `lastLocation`
  - `routePreview`
  - `recipientLabel` nullable
- `SafetyLiveShareRecipient` authorizes each explicitly invited accepted connection.
- `SafetyLiveShareCheer` stores a bounded original recording until the runner retrieves it.

Initial API:

- `POST /v1/safety/live-shares`
- `GET /v1/safety/live-shares/:id`
- `PATCH /v1/safety/live-shares/:id/location`
- `POST /v1/safety/live-shares/:id/end`
- `GET /live/:token`

`POST /v1/safety/live-shares` requires one to five accepted-connection user IDs and creates in-app notifications for them.

`GET /v1/safety/live-shares/:id` is an authenticated app lookup for notification routing. It is owner-scoped, returns only the live-share status and timestamps needed by the app, returns `404` for both unknown and unauthorized IDs, and returns `410` after expiry.

Rules:

- authenticated app APIs derive user identity from Firebase auth
- follower reads and voice writes require authentication plus an explicit recipient row
- location updates should be rate-limited and tolerate dropped updates
- end or expire sessions server-side even if the app crashes

## iOS Shape

New modules:

- `Safety/LiveShareStore.swift`
- `Safety/SafetyContactStore.swift`
- `Safety/LiveShareControls.swift`

Integration points:

- `RecordView`: pre-start share setup and handoff into the recorder
- `CameraHUDView`: active sharing indicator plus stop-sharing control
- `ActivityRecorder`: publishes snapshots already suitable for throttled location updates
- `APIClient`: authenticated start/update/end live-share calls

Do not put networking directly in `ActivityRecorder`; keep recording stable even if live-share sync fails.

## Current Implementation

### Current Local Slice

- `Safety/LiveShareStore.swift` owns local live-share state.
- `RecordView` has an off-by-default `Share live run` toggle that arms the next activity.
- `CameraHUDView` shows an active sharing control while a local share is running and lets the runner stop sharing.
- Finish and discard end the local share state.

### Current End-To-End Slice

- Backend routes live in `backend/src/routes/safety.ts`.
- Prisma models are `SafetyLiveShare` and `SafetyLiveSharePoint`.
- App APIs:
  - `POST /v1/safety/live-shares`
  - `PATCH /v1/safety/live-shares/:id/location`
  - `POST /v1/safety/live-shares/:id/end`
- `POST /v1/safety/live-shares` accepts selected accepted-connection user IDs, verifies the relationship, and creates in-app/push invitations.
- Invitees use authenticated `GET /v1/safety/live-shares/invited` and `GET /v1/safety/live-shares/invited/:id`; no public link is involved in the product flow.
- Live snapshots include exact route, pace, distance, elapsed time, and heart rate for invited users.
- `POST /v1/safety/live-shares/invited/:id/cheers` stores a bounded original AAC voice recording; the runner drains pending recordings from `GET /v1/safety/live-shares/:id/cheers`.
- `RecordView` presents an accepted-connection picker and creates the server share without a Share Sheet.
- Social shows active invitations in app; the follower screen provides the live map and a hold-to-record voice control.
- The runner polls for pending recordings and plays the unmodified audio through the live guide audio player.
- `LiveShareStore` sends throttled location updates from `ActiveSessionSnapshot`, currently every 10 seconds or 25 meters.
- Finish, discard, and the live HUD stop-sharing control call the backend end endpoint.
- If create or update fails, recording continues and the runner sees local stale/unavailable copy.

Apply backend schema changes with:

```sh
cd backend
npm run db:generate
npm run db:push
```

Emergency escalation remains outside this feature.

## Non-Goals

- emergency dispatch
- public spectator mode
- social feed live maps
- rich media in live tracking
