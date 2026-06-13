# Safety And Live Tracking

Open this when designing or implementing trusted-contact live tracking, route privacy, or safety controls.

## Product Gap

Strava Beacon, Runkeeper Go, MapMyRun, and AllTrails all make live tracking or location sharing feel like a serious trust feature. Outbound has local live activity UI and background GPS, but it does not yet let a runner share an active session with trusted people.

This is not just social sharing. It is safety, consent, privacy, and reliability.

## Product Position

Outbound should ship live tracking as a trust feature before trying to make it playful.

Near-term promise:

- "Let trusted people follow this run until I finish."

Do not lead with public maps, follower broadcasts, or social presence. Those can come later after privacy and identity are solid.

## User Experience

### V1 Trusted Link

Entry points:

- pre-start safety row on the activity start page
- live session safety control in the camera/map HUD
- Settings area for trusted contacts and default behavior

Flow:

1. Runner chooses `Share live run`.
2. Runner selects trusted contacts or creates a time-limited private link.
3. Outbound shows a clear confirmation before sharing begins.
4. Recipient opens a lightweight web view with current location, route so far, elapsed time, distance, last update time, and battery-friendly status copy.
5. Sharing ends automatically when the activity finishes, expires, or is manually stopped.

Default behavior:

- off by default
- no automatic public sharing
- do not expose photos, exact home address history, or past activities
- show the runner an obvious active-sharing indicator during the whole session

### V2 Trusted Contacts

Add a simple contact list once identity and notification plumbing are reliable:

- named trusted contacts
- one-tap start sharing with favorites
- optional expected-finish alert
- stale-location warning when the phone stops updating

### V3 Safety Escalation

Only after V1/V2 prove reliable:

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
  - `tokenHash`
  - `startedAt`
  - `expiresAt`
  - `endedAt`
  - `status`: active, ended, expired, revoked
  - `lastLocationAt`
  - `lastLocation`
  - `routePreview`
  - `recipientLabel` nullable
- `TrustedContact`
  - `id`
  - `userId`
  - `displayName`
  - `deliveryAddressEncrypted` or platform contact reference
  - `createdAt`

Initial API:

- `POST /v1/safety/live-shares`
- `PATCH /v1/safety/live-shares/:id/location`
- `POST /v1/safety/live-shares/:id/end`
- `GET /live/:token`

Rules:

- authenticated app APIs derive user identity from Firebase auth
- public live link uses an unguessable token, stored hashed server-side
- location updates should be rate-limited and tolerate dropped updates
- end or expire sessions server-side even if the app crashes

## iOS Shape

New modules:

- `Safety/LiveShareStore.swift`
- `Safety/LiveShareModels.swift`
- `Safety/LiveShareSettingsView.swift`
- `Safety/LiveShareControls.swift`

Integration points:

- `RecordView`: pre-start share setup and handoff into the recorder
- `CameraHUDView`: active sharing indicator plus stop-sharing control
- `ActivityRecorder`: publishes snapshots already suitable for throttled location updates
- `APIClient`: authenticated start/update/end live-share calls

Do not put networking directly in `ActivityRecorder`; keep recording stable even if live-share sync fails.

## Rollout Plan

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
- Recipient route:
  - `GET /live/:token`
  - `GET /live/:token?format=json` for browser polling
- `RecordView` creates the server share before countdown when `Share live run` is armed.
- iOS presents the returned public link in the system Share Sheet.
- `LiveShareStore` sends throttled location updates from `ActiveSessionSnapshot`, currently every 10 seconds or 25 meters.
- The public page polls every 10 seconds and shows route preview, current/last location, elapsed time, distance, update age, stale state, and ended/expired state.
- Finish, discard, and the live HUD stop-sharing control call the backend end endpoint.
- If create or update fails, recording continues and the runner sees local stale/unavailable copy.

Apply backend schema changes with:

```sh
cd backend
npm run db:generate
npm run db:push
```

Trusted contacts, notification delivery, route privacy zones, and emergency escalation remain future work.

### Milestone 1: Private Live Link

- backend session create/update/end endpoints: shipped
- minimal public live viewer: shipped
- iOS start/stop control: shipped
- active sharing indicator: shipped
- automatic expiry and finish cleanup: shipped

### Milestone 2: Trusted Contacts

- manage favorites in Settings
- share via system share sheet or stored contact path
- stale-location and expected-finish copy

### Milestone 3: Route Privacy

- privacy zones
- reduced precision near sensitive locations
- default share templates for run, hike, and bike

## Non-Goals For V1

- emergency dispatch
- public spectator mode
- social feed live maps
- rich media in live tracking
- background push notifications to recipients
