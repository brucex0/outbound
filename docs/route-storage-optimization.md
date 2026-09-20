# Route and Activity Payload Storage

## Final architecture

Routes are time-series data and are stored independently from activity metadata.

- **iOS local store:** `activities.json` contains activity metadata only. Each activity owns `UUID/route.bin`, a compact versioned binary sidecar. Photos remain in the same activity directory.
- **Android local store:** Room already stores route points in `activity_track_points`, separate from the activity row.
- **Backend:** `Activity.routeBlob` is a compact versioned binary payload and `Activity.routeMetadata` contains only visibility/elevation attribution. The old `Activity.route` JSON column is removed by the migration.
- **API:** uploads may use the readable `{ route: { points } }` contract; the server immediately encodes it. Activity downloads expand the blob to that contract. The Social feed returns a shape-only encoded-polyline preview, while GeoJSON is reserved for exports and explicit interoperability boundaries.

Updating an activity title, reflection, photos, or client extras therefore does not rewrite the route sidecar/file or backend route blob unless route points actually changed.

## Storage medium decision (final)

Backend route bytes intentionally live in Postgres (`Activity.routeBlob`, `bytea`) — this is the final state, not an interim step toward files/object storage:

- The blob is written once at upload and never rewritten by activity metadata updates.
- Postgres TOAST stores bytea values out-of-line, so the activity row stays small and non-route reads pay nothing for it.
- Measured with the production codec: a 21 km / 1,850-point route encodes to **13.7 KB** versus 164 KB of legacy GeoJSON (12× smaller) — smaller than one photo.
- Transactional with the activity row; sync restore remains a single request.

Object storage (Firebase Storage, following the photo/avatar pattern in `activityPhotoStorage.ts`) remains a documented future option if a driver appears: route sizes growing well beyond tens of KB (watch imports, all-day hikes, GPX), or a need for clients to download routes directly. That move would require a backfill script, delete lifecycle handling, and either proxied reads or a signed-URL client contract on iOS and Android.

## Compact encoding

The route codec uses:

- latitude/longitude rounded to six decimal places and delta encoded;
- whole-second timestamp deltas;
- elevation and vertical accuracy quantized to decimeters;
- a per-point flag for segment boundaries and optional values;
- signed varints and a small versioned header.

The in-memory iOS/Android models remain normal route points. Encoding happens only at persistence/sync boundaries, preserving map, export, and editing behavior.

### Social route previews

`/v1/social/home` and `/v1/social/together` return routes as `polyline5` previews capped at 120 points. The payload includes the encoded shape, decoded point count, and geographic bounds; it intentionally omits timestamps, altitude, accuracy, visibility, and elevation attribution. This keeps the paginated feed small while activity sync remains the source for full-fidelity route data.

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

Production uses Prisma schema push instead of migration execution. Its `db:push` command first runs `prepareActivityRouteStorage`, which creates the new columns when needed, encodes every legacy route, and fails closed if any route cannot be converted. Only after that preparation succeeds may Prisma remove the legacy JSON column.

## Verification

The backend codec round-trip is covered by the local smoke check and should be exercised with 12 km, 21 km, paused, segmented, and variable-accuracy routes. Record raw/normalized point counts, maximum map deviation, distance/elevation drift, encoded bytes, API bytes, local bytes, and encode/decode time. Verify activity upload/restore, photos, followed routes, recognition badges, and reflection independently of route storage.
