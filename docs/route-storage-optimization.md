# Route and Activity Payload Storage

## Decision

Use one canonical route representation and one purpose-built client extras object. Do not serialize `SavedActivity` inside `Activity.clientData`.

## Route plan

Normalize the raw Core Location stream after recording. Keep first/last points, segment boundaries, pause/gap boundaries, meaningful turns, and enough points for a 5–10 m visual error bound. Normal movement should target approximately 10–15 seconds and/or 15–25 m between retained points. The current `distance >= 10 || time >= 15` filter is too permissive for dense 3–5 second tracks.

Persist a versioned compact route separately from activity metadata. Use fixed-point microdegree coordinates, delta encoding, whole-second timestamp deltas, integer-decimeter elevation, quantized vertical accuracy, and a segment bitset. Keep `SavedRoutePoint` as the in-memory model; encode/decode at persistence and sync boundaries. GeoJSON is an export/API expansion format, not the canonical stored format.

## Client data contract

`Activity.clientData` is an `ActivityClientExtras` object containing only client-owned fields not represented by dedicated activity columns:

- guide nudge and walking step count;
- health detail, goal, energy, source, gear, manual edits, and indoor metadata;
- cadence, heart-rate zones, recording session, and activity event metadata;
- followed-route metadata and recognition badge IDs.

It must not contain route, photos, sync state, reflection, title, timestamps, duration, distance, pace, elevation, heart-rate summary, or activity type. Those values have one canonical owner in the activity columns/response. The activity list response returns canonical fields and route separately, while `clientData` carries only extras.

## Cutover and migration

This is an immediate clean contract cutover. The one-time migration command `npm run migrate:activity-client-data` extracts the allowed extras from existing full snapshots and removes route/photos/sync/canonical fields. New clients have no decoder for the old snapshot shape. Run the migration before deploying the new iOS client; reset development data instead when convenient.

Never retain both full route copies. If a legacy response is ever needed, generate it at request time rather than storing it.

## Verification

Benchmark 12 km and 21 km routes, paused routes, segmented routes, and variable-accuracy routes. Record raw/normalized point counts, maximum map deviation, distance/elevation drift, encoded bytes, API bytes, local bytes, and encode/decode time. Verify activity upload/restore, photos, followed routes, recognition badges, and reflection independently of route storage.
