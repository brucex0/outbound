# Account Preferences and Configuration

Open when adding a setting that should follow an account across phones, changing sync, or deploying the configuration schema.

## Ownership and Scope

- Existing general settings remain in `UserPreferences.data`, served by `GET`/`PUT /v1/auth/me/preferences`. That endpoint still replaces a snapshot; it does not gain conflict protection in this change.
- Stretch selections, saved stretch customizations, and per-sport launch preferences use `UserConfiguration`: one row per `(userId, key)`, with an integer revision, JSON value and update timestamp. Account deletion cascades to these rows.
- Clients call authenticated APIs, never Postgres directly. The backend derives ownership from the verified session. Both iOS and Android use the same IDs, meters, seconds, and wire contract.
- Unsaved routine edits, launch drafts, recording recovery, permissions, media and audio downloads stay on the device. A restored preference does not grant permissions or alter an active recording/stretch player.

## Configuration Contract

- `GET /v1/auth/me/configuration` returns `{ records: [{ key, revision, value }] }`; a new account returns an empty list. Include reset tombstones in responses.
- `PATCH /v1/auth/me/configuration` takes `{ key, expectedRevision, value }`; revision `0` means the key does not exist. Return `{ record: { key, revision, value } }` on success.
- Creation starts at revision 1. Updates increment the revision. Compare and write atomically under an account-row lock, including concurrent first writes.
- A stale revision returns HTTP 409 and the current record. Clients retain the accepted server value for that key; unrelated pending keys remain queued. This policy deliberately resolves simultaneous edits without merging the internals of a routine or sport preference. An edit made locally while an earlier upload is in flight remains queued against the newly accepted revision.
- Reset sends explicit JSON `null` and increments the revision. Keep the row so an offline phone cannot silently resurrect a deleted customization.
- Allowed keys/values:

| Key | Value |
| --- | --- |
| `stretch/last` | `{ selection: templateID }` |
| `stretch/standing` | `{ selection: templateID }` |
| `stretch/custom/<templateID>` | `{ entries: [{ movementID, seconds }] }` |
| `launch/lastSport` | `{ selection: sportID }` |
| `launch/<sportID>` | `{ launch: { preferredGoalModeRawValue?, goalModeStartHistory, distanceMeters?, timeSeconds?, calories? } }` |

- Sport IDs: `run`, `walk`, `hike`, `bike`, `swim`, `strength`, `mobility`. Clients only expose supported sports. Goal modes: `freestyle`, `distance`, `time`, `calories`.
- Use canonical catalog template and movement IDs. Validate 1–20 unique movements, allowed 15/20/25/30-second durations, and the template's dynamic/static mode. Backend template modes are generated from `shared/stretch/catalog.json`.
- Do not upload display names, translations, illustrations, instructions, or user-entered prose in this contract.

## Client Behavior

- Cache accepted values and a durable outbox separately, scoped to the internal account ID. New phones fetch remote records without uploading app defaults. Signed-out configuration uses a separate guest cache and is not automatically copied into an account.
- Apply saves locally immediately; debounce uploads. Retry on app activation and network availability. Failed uploads remain queued across process restarts. Log operation plus safe status/error category, never payloads, exact targets, account IDs, or credentials.
- iOS adopts existing local stretch settings once for the first claiming account, plus that account's existing launch preferences. Existing remote records win adoption conflicts. Other accounts cannot claim the same old stretch settings.
- Android is unreleased: use the new `account_configuration_v1_<account>` preferences directly. Do not migrate the old stretch preferences or recording launch snapshot. Existing development-only stretch edits must be recreated; an optional full reset is `adb shell pm clear com.plainstride.outbound.debug`. No Room reset is required.
- Stretch selection persists only on Start; customizations on Save; Reset queues a tombstone. Keep standing/outdoor fallback and exclude the warm-up from post-save restoration. Playback holds its immutable routine.
- Targets persist only after recording starts. Preserve other mode targets for the same sport. Retain the existing iOS rule: a goal mode becomes the learned default after three consecutive starts; Android uses that same rule for the shared preference. Curated/planned/race launches do not update manual defaults.
- A late remote refresh may update untouched setup. Explicit local choices and unsaved drafts remain in the current screen; active playback/recording is never rewritten by sync.
- Analytics reuse `preference_changed` with `change_type=account_configuration_sync` and bounded `selection_type=saved|conflict|failed`. Existing start/editor events continue to describe user actions. Never include configuration values or IDs in sync analytics.

## Deployment

Deploy the backend/table before distributing clients that use this API. This is an additive table; do not reset production data.

```sh
cd backend
npm run db:generate
npx prisma db push --skip-generate
npm run build
```

Use the intended deployment's existing database environment and the normal backend deployment runbook. No database rebuild, data reset, or manual account backfill is needed. Until deployment, clients keep changes locally and report API failures in diagnostics.

## Verification

- Backend TypeScript build, iOS arm64 Simulator build, Android `:app:assembleDebug`, and `git diff --check` passed. No test suite run.
- Isolated local Postgres/API manual exercise: empty account, save/restore numeric target and ordered stretch entries, independent keys, simultaneous same-revision updates (one success/one 409), reset/stale resurrection conflict, invalid duration/duplicate/mode/key validation, separate account ownership, missing authentication, and account-deletion cascade.
- Still requires device acceptance: two phones on the same account, offline edit/relaunch/reconnect, switching accounts in app, late refresh with an open draft, foreground refresh, complete stretch playback and audio, and start/cancel behavior on each platform. API checks and builds do not establish those UI/runtime behaviors.
