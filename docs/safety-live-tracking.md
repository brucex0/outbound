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
- Settings > Trusted Contacts lets the runner mark accepted connections as trusted and optionally invite all of them by default for each new activity
- the cheer picker lists trusted contacts first and preselects them; when none are configured it links directly to Trusted Contacts settings
- do not expose photos, exact home address history, or past activities
- show the runner an obvious active-sharing indicator during the whole session

Android omits absent optional strings when creating live shares because the backend rejects explicit nulls. Failed creation retains the pending selection, records the existing `live_share_started` failure outcome, logs safe status/category diagnostics, and shows a temporary toast. A later recording transition can retry; no background retry is scheduled.

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
- Prisma models are `SafetyLiveShare`, `SafetyLiveSharePoint`, and `SafetyTrustedContact`.
- App APIs:
  - `POST /v1/safety/live-shares`
  - `PATCH /v1/safety/live-shares/:id/location`
  - `POST /v1/safety/live-shares/:id/end`
  - `GET /v1/safety/trusted-contacts`
  - `PUT /v1/safety/trusted-contacts`
- Trusted contacts are server-owned: `SafetyTrustedContact` stores accepted-connection pairs so the list survives delete/reinstall on both platforms. iOS marks accepted connections in settings; Android picks from the same accepted connections (the phone contact book is never persisted server-side).
- `POST /v1/safety/live-shares` accepts selected accepted-connection user IDs, verifies the relationship, and creates in-app/push invitations.
- Invitees use authenticated `GET /v1/safety/live-shares/invited` and `GET /v1/safety/live-shares/invited/:id`; no public link is involved in the product flow.
- Live snapshots include exact route, pace, distance, elapsed time, and heart rate for invited users.
- `POST /v1/safety/live-shares/invited/:id/cheers` stores a bounded original AAC voice recording; the runner drains pending recordings from `GET /v1/safety/live-shares/:id/cheers`.
- `RecordView` presents an accepted-connection picker and creates the server share without a Share Sheet.
- Starting an armed activity sends each selected connection an in-app/push invitation and confirms the invitation with an in-app toast.
- Tapping a live-cheer push opens the authenticated follower screen directly using the share ID in the push payload; tapping the same item in the Social inbox opens the same destination.
- Social shows active invitations in app; the follower screen provides the live map and a hold-to-record voice control.
- A failed initial follower lookup shows an unavailable state with retry instead of an indefinite loading indicator. The follower requests microphone access only when the recipient first holds to record, matching iOS. The hold control tracks the button's press state, starts only after permission is already granted, and shows brief feedback for permission, recorder-start, and send outcomes.
- The runner receives an Ably wake-up event for a new recording, then fetches and plays the unmodified audio through the live guide audio player.
- Active runner location and group-run locations publish over Ably Pub/Sub. Invited viewers subscribe to the one session channel; group runners publish and subscribe to the one group channel. REST remains responsible for session authorization, initial snapshots, one-minute recovery checkpoints, and voice audio. Cheer uploads publish only a `cheer.available` wake-up event; audio remains authenticated REST data.
- The backend issues two-minute Ably tokens bound to the authenticated Plainstride user and exact active session channel. The SDK renews them while the session remains authorized. Group participants receive publish/subscribe; a live-share owner receives publish/subscribe; invited cheerers receive subscribe only. Never place `ABLY_API_KEY` in either app.
- Configure the Ably channel namespace without message history/persistence. Live location is ephemeral and clients fetch an authenticated REST snapshot when opening or recovering a session.
- Fetching a voice cheer records delivery only. The app records `playedAt` after successful audio playback, so the follower sees a truthful `Sent → Delivered → Heard` progression.
- After playback, the runner sees a compact, dismissible banner and can send one explicit `❤️ Heard you` acknowledgment. The follower's persistent cheer-status indicator updates when that acknowledgment arrives.
- Cheer receipts store `deliveredAt`, `playedAt`, and `acknowledgedAt`; the follower APIs expose only the current follower's latest cheer receipt.
- Analytics records voice-cheer playback and acknowledgment outcomes without audio content, sender identity, or location.
- Android adapts outgoing location maps to Gson JSON objects for the Ably Java SDK and converts received JSON objects back to field maps. Recovered recording publication and its sharing toggle use the recorder's restored event context. The local recording map starts at zoom 17 for more visible movement; manual pan and recenter behavior are unchanged.
- iOS and Android group sharing publish each new GPS measurement over Ably with a one-second minimum interval, replacing the former 10-second/25-meter throttle. Both keep one-minute REST recovery checkpoints. Repeated/older fixes and measurements older than 15 seconds (or more than 5 seconds in the future) are not republished. `recordedAt` is the GPS measurement time, not the UI snapshot time; Android fractional-second ISO timestamps are accepted by iOS.
- Group maps retain newer realtime positions when older REST checkpoints or out-of-order messages arrive. Server leave/finish/end state remains authoritative. Runner pills show localized update age and reported GPS accuracy in meters; pins fade after 15 seconds without a fresh measurement. Accuracy is uncertainty, not a guarantee that runners 15 meters apart can be ordered correctly.
- iOS and Android event-map pills include RSVP attendees and actual starters, including `participating` entries created without an RSVP. Matching live-session members appear before the next event-roster refresh. Tapping a pill or expanded Group card row focuses the available runner location; absent locations use the same temporary unavailable toast. Other presence-card surfaces remain informational. Android uses the restored recording's event ID to match its live session, and repeated participant selections refocus after a map pan.
- The separate invited-cheerer stream also uses a one-second minimum interval and GPS measurement timestamps. Followers extend the checkpoint route with each newer Ably location. Follower and runner maps share route styling, marker, 400-meter camera framing, and heading; the realtime payload carries course for follower rotation. The runner map follows filtered track points to reduce raw GPS jitter.
- Finishing sends the reconciled final snapshot before ending the share. Followers see elapsed time and current pace while the share is active, then average pace calculated from final elapsed time and distance after it ends.
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

## Live Location Verification

- Build only: use the iOS simulator build in `docs/build-test-device.md` and `cd android && ./gradlew :feature:safety:compileDebugKotlin :feature:recording:compileDebugKotlin`.
- Device acceptance: join one session from iOS and Android, move together with a roughly 15-meter gap, and compare displayed age/accuracy. Verify fresh fixes arrive about once per second while GPS and connectivity permit; this is a publish throttle, not an end-to-end latency guarantee.
- Stop location/network delivery: update age must continue advancing, and pins must fade after 15 seconds. Restore delivery: a newer fix restores the fresh state. Confirm an older checkpoint cannot move the pin backwards and leaving/finishing still ends sharing.
- Confirm only a new GPS measurement publishes; stationary sessions must not refresh an old measurement's timestamp. Check weak GPS and reconnect paths on devices; builds alone do not establish physical positioning accuracy or latency.

### Focused UI Tests

- iOS: `xcodebuild -project ios/Outbound/Outbound.xcodeproj -scheme GroupRecoveryUI -destination 'id=<simulator>' -parallel-testing-enabled NO -only-testing:OutboundUITests/LiveLocationFreshnessUITests CODE_SIGNING_ALLOWED=NO test`. `LiveLocationFixture` serves a loopback `/live/group-runs` API, so the run covers displayed update age, reported GPS accuracy, the 15-second fade with no incoming fixes, an older recovery checkpoint not replacing a fresh fix, and finish still ending the share. Grant location to the simulator (`xcrun simctl privacy <sim> grant location-always plainstride.outbound`) so the app's own location prompt does not block start.
- Android: `cd android && ./gradlew :feature:recording:connectedDebugAndroidTest` runs `GroupParticipantStripTest` against `GroupParticipantStrip` with a hoisted display clock; pills use a stub avatar so the Hilt-backed `SocialAvatar` path is not covered.
- These harnesses do not exercise the publish throttle, original-timestamp writes, Ably delivery, or physical GPS accuracy; those still need the device acceptance pass above.

### Test Runs And Roster Recovery

- Debug simulated runs retain accelerated timestamps in the recorded track, but live sharing stamps each **newly generated fix** with its real delivery time. A stopped simulation clock does not continually refresh an old fix. Normal GPS sharing keeps the original sensor measurement time. This prevents 10×/60× simulation or manual time advances from being rejected by the live freshness gate on either platform.
- Both clients refresh the authorized group roster every 15 seconds while sharing, including when recording is paused. Unknown realtime senders trigger a roster refresh before their fix is applied. Missing, revoked, or ended sessions stop the stale local connection; an explicit new join remains necessary after revoked consent.
- A fresh server join can replace an older cached finished/left participant. Newer location preservation applies only between active/stale records, never across a terminal lifecycle state. Recovering an old session also re-evaluates Today’s unconsumed default for the selected activity without re-enabling an explicit opt-out.
- Android stacks the Debug test-run card and Group presence card vertically. The simulation clock button shares the time-rate row so it remains reachable at narrow phone widths.
- The Android card stack ends above the map recenter button's full touch target, with a 12 dp gap. Tall rosters scroll within that space so the sharing switch remains reachable without the map control covering it. Sharing and recenter callbacks retain their existing analytics.
