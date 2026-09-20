# Route Storage Optimization

Open this when changing recorded activity route sampling, encoding, persistence, or sync.

## Problem

Recorded routes currently vary significantly in point density because Core Location controls delivery frequency. The app requests high-quality navigation updates with a one-meter distance filter, but this does not guarantee a fixed sampling interval. Device, GPS conditions, phone/watch source, batching, power state, and motion can produce materially different tracks.

The persisted route is a verbose GeoJSON Feature containing full-precision coordinate and elevation numbers, ISO timestamps, and one vertical-accuracy value per point. A 21 km route can therefore be several times larger than a shorter route when it is delivered at a higher frequency.

The database currently stores this route as JSONB. PostgreSQL already compresses JSONB, so the primary target is the logical/API/local representation and point-count normalization, not a database-only compression change.

## Goals

- Make persisted route size depend primarily on route distance and meaningful geometry, not Core Location delivery behavior.
- Preserve map fidelity, start/end points, meaningful turns, pauses, and segment breaks.
- Keep enough time/elevation data for activity detail, pace interpretation, elevation display, and GPX export.
- Avoid storing false precision from GPS and terrain estimates.
- Keep route data out of the large activity metadata document and local activity manifest.
- Decode routes lazily and avoid sending full geometry in activity-list responses.
- Support a low-complexity migration from the current GeoJSON format.

## Canonical persistence design

Persist a versioned compact route blob separately from activity metadata.

```text
activity metadata:
  routeEncodingVersion
  routePointCount
  routeByteLength
  routeFile/column reference

route blob:
  version and header
  origin coordinate
  start timestamp
  delta-encoded coordinates
  delta-encoded timestamps
  quantized elevation
  optional quantized vertical accuracy
  segment-start bitset
```

Use fixed-point integers and signed varints:

- latitude/longitude: integer microdegrees (`1e6` scale)
- coordinates: deltas from the previous point
- timestamp: seconds from route start, delta encoded
- elevation: integer decimeters
- vertical accuracy: integer decimeters or sparse exceptions
- segment breaks: bitset rather than a Boolean per point

Use a binary/Bytes (`bytea`) column on the backend and a dedicated route file per activity on iOS. Do not base64-encode the canonical backend representation unless the database abstraction requires it; base64 adds approximately 33% overhead.

GeoJSON remains an expansion format for export, compatibility, or clients that explicitly request it. It is not the canonical stored form.

## Post-recording normalization

Do not attempt to control final storage size through Core Location settings. Normalize after recording, before persistence and upload.

The first implementation should:

1. retain the first point;
2. retain the final point;
3. preserve segment boundaries and pause/resume gaps;
4. resample normal movement at approximately 10–15 seconds and/or 15–25 meters;
5. preserve meaningful turns;
6. preserve points around long gaps and pauses;
7. apply an error-bounded line simplifier with a target maximum visual error of approximately 5–10 meters;
8. retain a point when the simplifier would otherwise exceed that error bound.

The current `distance >= 10 || time >= 15 || meaningfulTurn` rule is too permissive for dense tracks: a 3–5 second track can satisfy the ten-meter condition on nearly every update. Replace it with a deterministic resampling/simplification pass with explicit error and maximum-gap rules.

The normalized route is the default activity route. Raw locations should not be persisted by default. If raw data is needed for debugging or future export fidelity, keep it as a separate optional compressed diagnostic artifact rather than embedding it in the activity record.

## Precision policy

- Coordinates: six decimal places / microdegree integers. Five decimal places may be evaluated for display-only routes.
- Elevation: decimeters are the default; do not preserve 14–17 decimal digits from terrain or GPS data.
- Vertical accuracy: decimeters or one decimal meter precision; omit it from normal display routes unless a consumer needs it.
- Invalid or extreme accuracy values should be filtered or stored only as diagnostic exceptions.
- Timestamp precision: whole seconds are sufficient for persisted activity history and export; preserve irregular gaps using deltas.

## Backend boundaries

- Store compact route bytes and scalar route metadata on `Activity`.
- Keep `splits`, reflection, guide analysis, and activity summaries separate from route bytes.
- Activity list endpoints return summaries and route metadata, not expanded geometry.
- Activity detail expands the route only when requested.
- Route export decodes the compact blob and generates GPX/GeoJSON at the boundary.
- Spatial search, if needed later, can use a separately maintained simplified spatial geometry; it should not require decoding the full route blob.

## iOS boundaries

- Keep `SavedRoutePoint` as the in-memory compatibility model initially.
- Add a compact route encoder/decoder at the persistence and sync boundary.
- Store route files separately from `activities.json` so metadata updates do not rewrite route data.
- Load display geometry lazily for history/detail screens.
- Keep guidance and live recording working on `CLLocation` values; only normalize at the persistence boundary unless a separate live-memory budget requires earlier resampling.
- Continue generating route previews from the normalized route.

## Migration and compatibility

Backward compatibility is optional but inexpensive:

1. Add an encoding version and compact route field/file.
2. New clients write only the compact format.
3. New clients read compact routes first and fall back to legacy GeoJSON.
4. The backend accepts legacy uploads during the migration window.
5. Decode either format into the existing in-memory route model.
6. Expand compact routes only for legacy API consumers or explicit export.
7. Migrate old routes lazily on activity update or explicit access.
8. Remove the legacy path after all supported clients understand the compact format.

Do not keep both full legacy and compact copies indefinitely. If a legacy compatibility response is needed, generate it at request time.

## Verification

Benchmark representative routes before rollout:

- 12 km low-frequency route
- 21 km high-frequency route
- route with pauses and long gaps
- route with multiple segments
- route with poor/variable vertical accuracy
- route with terrain-corrected elevation

Record:

- raw point count
- normalized point count
- maximum geometric deviation
- distance and elevation differences
- logical bytes
- physical database bytes
- API response bytes
- local file bytes
- encode/decode time

Acceptance criteria:

- normalized size is stable across phone/watch sampling differences;
- map deviation stays within the selected error bound;
- distance and activity summaries remain within agreed tolerances;
- pauses and segment breaks survive round-trip encoding;
- GPX/GeoJSON exports remain valid;
- old route data remains readable during migration.
