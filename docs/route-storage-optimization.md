# Route and Activity Payload Storage

## Final architecture

Routes are time-series data and are stored independently from activity metadata.

- **iOS local store:** `activities.json` contains activity metadata only. Each activity owns `UUID/route.bin`, a compact versioned binary sidecar. Photos remain in the same activity directory.
- **Android local store:** Room already stores route points in `activity_track_points`, separate from the activity row.
- **Backend:** `Activity.routeBlob` is a compact versioned binary payload and `Activity.routeMetadata` contains only visibility/elevation attribution. The old `Activity.route` JSON column is removed by the migration.
- **API:** uploads may use the readable `{ route: { points } }` contract; the server immediately encodes it. Downloads expand the blob to that contract. GeoJSON is produced only for exports, social/public route geometry, or other explicit presentation boundaries.

Updating an activity title, reflection, photos, or client extras therefore does not rewrite the route sidecar/file or backend route blob unless route points actually changed.

## Compact encoding

The route codec uses:

- latitude/longitude rounded to six decimal places and delta encoded;
- whole-second timestamp deltas;
- elevation and vertical accuracy quantized to decimeters;
- a per-point flag for segment boundaries and optional values;
- signed varints and a small versioned header.

The in-memory iOS/Android models remain normal route points. Encoding happens only at persistence/sync boundaries, preserving map, export, and editing behavior.

## Sampling policy

Normalize the raw Core Location stream after recording. Keep first/last points, segment boundaries, pause/gap boundaries, meaningful turns, and enough points for a 5–10 m visual error bound. Normal movement should target approximately 10–15 seconds and/or 15–25 m between retained points. The current `distance >= 10 || time >= 15` filter is too permissive for dense 3–5 second tracks and should be tightened in a separate recording-quality change after visual benchmarking.

## Client data contract

`Activity.clientData` is an `ActivityClientExtras` object containing only client-owned fields not represented by dedicated activity columns. It must not contain route, photos, sync state, reflection, title, timestamps, duration, distance, pace, elevation, heart-rate summary, or activity type. There is one canonical owner for every field.

## Migration

Deploy the Prisma migration `20260919000000_compact_activity_route`. It creates `routeBlob`/`routeMetadata`, copies old route JSON into a temporary blob, and drops `Activity.route`. Then run:

```bash
cd backend
npm run migrate:activity-routes
npm run migrate:activity-client-data
```

`migrate:activity-routes` rewrites the temporary JSON blobs into the compact binary format. The application can read the temporary JSON form during the short migration window, so the route remains recoverable if the commands are run separately. New uploads are compact immediately.

## Verification

The backend codec round-trip is covered by the local smoke check and should be exercised with 12 km, 21 km, paused, segmented, and variable-accuracy routes. Record raw/normalized point counts, maximum map deviation, distance/elevation drift, encoded bytes, API bytes, local bytes, and encode/decode time. Verify activity upload/restore, photos, followed routes, recognition badges, and reflection independently of route storage.
