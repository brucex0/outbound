# Live Group Run Sharing Design

## Goal

Add live group run sharing so runners can see friends on their in-session map when everyone has explicitly joined the same active group share.

This bridges Outbound's safety live tracking and future Social/Club features without creating ambient friend-location tracking. The V1 promise is:

- "Start or join a private group run, then see the people running with me until the run ends."

## Product Scope

V1 supports informal invite-link group runs:

1. A runner opens the activity start screen.
2. They create or join a live group share.
3. Creating a group produces a private invite link shared through the system Share Sheet.
4. Joined runners who actively share their own location appear on each other's in-run map.
5. The group share ends when the runner finishes, stops sharing, leaves the group, or the session expires.

Runner-to-runner visibility is mutual. A runner must share their own active location to see the in-app group map. Spectators remain separate and should use the existing private safety-style viewer.

## Non-Goals

- Friend graph or always-on friend location.
- Public group maps.
- Route trails for other runners.
- Club scheduling dependency.
- Nearby discovery, QR joining, or short-code joining.
- Rich chat, cheers, comments, or moderation surfaces.
- Emergency escalation.

## Map Experience

Use a "pins plus runner strip" model.

- The current runner's dot remains primary and centered by default.
- Other runners appear as avatar pins on the map.
- A compact runner strip shows relative status, for example `Maya - 0.2 mi ahead - last 8s`.
- Tapping a pin or strip row temporarily focuses the map on that runner.
- A recenter control returns the map to the current runner.
- Off-screen runners appear as edge indicators with avatar, distance, and rough bearing.
- Stale runners fade visually and show `last seen` copy before disappearing after a timeout.

V1 shares only current location for other runners. It does not draw their route history. Exact pins are acceptable while the explicit active group share is running; route privacy zones remain a future layer before broader social route sharing.

## Presence Rules

Participant states:

- `active`: fresh location update and currently sharing.
- `stale`: no fresh update within the freshness window.
- `left`: runner stopped sharing or left the group.
- `finished`: runner ended their activity.
- `expired`: group session is no longer active.

V1 should collapse `left`, `finished`, and lost signal into the same user-facing faded last-seen treatment, then remove the runner after a short timeout. More detailed status language can come later if runners need it.

Suggested freshness behavior:

- Send updates on a throttle similar to safety live sharing, such as every 10 seconds or 25 meters.
- Treat a participant as stale after roughly 45-60 seconds without an update.
- Remove stale or ended participants from the runner strip after roughly 5 minutes, unless the current runner has focused them.

## Privacy Rules

- Group location sharing requires explicit per-session consent.
- There is no automatic public sharing.
- Group sessions must expire server-side.
- The runner can stop sharing or leave the group during the activity.
- Seeing runner locations in-app requires mutual sharing.
- Spectator links are view-only and separate from the mutual runner group.
- Recipients should not get profile history, past activities, photos, or route trails through V1 group sharing.

## Architecture

Add a small backend `live` domain for active live sessions instead of overloading `safety` or waiting for full Social backend readiness.

Core backend concepts:

- `LiveSession`
  - `id`
  - `creatorUserId`
  - `kind`: `group_run`
  - `inviteTokenHash`
  - `startedAt`
  - `expiresAt`
  - `endedAt`
  - `status`: `active`, `ended`, `expired`
- `LiveParticipant`
  - `id`
  - `sessionId`
  - `userId`
  - `displayName`
  - `status`: `active`, `left`, `finished`
  - `joinedAt`
  - `leftAt`
  - `lastLocationAt`
  - `lastLocation`
  - `lastActivitySnapshot`

Suggested APIs:

- `POST /v1/live/group-runs`
- `POST /v1/live/group-runs/join`
- `GET /v1/live/group-runs/:id`
- `PATCH /v1/live/group-runs/:id/participants/me/location`
- `POST /v1/live/group-runs/:id/participants/me/leave`
- `POST /v1/live/group-runs/:id/end`

Polling is acceptable for V1 and matches the current safety live viewer shape. A later server-sent events or WebSocket transport can reuse the same domain model.

## iOS Shape

Add `LiveGroupStore` as the client-side owner of live group state. Keep networking out of `ActivityRecorder`.

Responsibilities:

- Create and join live group sessions.
- Prepare invite link share copy.
- Track current group session, participant list, stale state, and local sharing state.
- Send throttled location updates from `ActiveSessionSnapshot`.
- Poll group participant locations while an activity is active.
- Leave or end group sharing on finish, discard, explicit stop, or expiry.

Integration points:

- `RecordView`: create/join group setup on the activity start screen and active-session lifecycle hooks.
- `ActivityRecorder`: continues publishing local snapshots; it does not know about groups.
- `LiveMapView` or the active map surface: renders participant overlays from a UI-ready model.
- `CameraHUDView`: shows active group-sharing indicator and stop-sharing control if needed.
- `APIClient`: typed live group endpoints.

## Error Handling

Recording must continue if group sharing fails.

- Create failure: stay on the start screen and show unavailable copy.
- Join failure: explain that the invite expired or is unavailable.
- Update failure: keep recording, mark local group sharing as stale/unavailable, retry on the next throttle.
- Poll failure: keep the last known participant state briefly, then stale it out.
- End/leave failure: update local UI immediately and retry best-effort in the background if the app remains active.

## Rollout

1. Backend `live` models and group-run endpoints.
2. iOS `LiveGroupStore` create/join/leave/update/poll flow.
3. Activity start screen entry for create/join group share.
4. Active map participant pins, runner strip, focus, recenter, stale state, and edge indicators.
5. Lifecycle cleanup on finish, discard, stop sharing, and expiry.

The existing one-way safety live share remains separate. Future work can connect Club scheduled runs, friend-to-friend live watching, QR/code joining, privacy zones, and richer Social presence to the `live` domain.

Apply backend schema changes with:

```sh
cd backend
npm run db:generate
npm run db:push
```
