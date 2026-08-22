# Community Route Library

Open this when implementing saved routes, route discovery, route import/export, route privacy, or route-guided recording.

## Product Contract

- Routes are a first-class community object available from Today, activity setup, Social, and Me.
- Every route published by the current product is public and discoverable. The data model retains `public`, `unlisted`, and `private` visibility values for future use, but the UI does not offer visibility controls yet.
- `Save Route` appears only on the signed-in runner's own saved activity. A runner cannot republish somebody else's activity as their route.
- Saving a community route creates an independent canonical route. Deleting the source activity does not silently delete the published route.
- Saving another runner's route creates a bookmark; it does not copy geometry or transfer ownership.
- GPX and GeoJSON import creates a prepared route for planning and recording. Imported routes persist on the device, appear above server-backed routes in the route library, and remain available until the runner explicitly deletes them. Imported geometry cannot be published directly. After the runner records and saves their own activity, that activity becomes eligible for `Save Route`.

## Discovery UX

- Today exposes `Explore routes` beside the primary workout and Quick Start actions.
- Activity setup opens the route picker directly so a route can be combined with a freestyle or planned workout. The picker requests location and refreshes nearby routes automatically, supports direct row selection, lets the selected row be tapped again to remove the route, keeps the choice pending until confirmation, and closes after applying the choice. `Close` leaves the activity unchanged.
- Social's community menu links to route discovery and Social may show nearby/popular route cards.
- Me exposes `My Routes`, containing routes owned or bookmarked by the runner.
- Discovery supports nearby results, text/location search, current map area, distance, elevation, activity type, and route shape as the dataset grows.
- Route detail shows the map, distance, elevation, shape, creator, saves, completions, and `Start Route`.

## Canonical Data

- A route is an ordered list of valid longitude/latitude pairs with optional altitude.
- Activity timestamps, pauses, photos, and other private activity metadata never enter the community-route response.
- The server owns public route geometry, summary metrics, ownership, lifecycle, visibility, and aggregate popularity.
- Local iOS state is a cache plus durable device-local imported-route state, not the source of truth for published routes.
- GPX and GeoJSON are generated or parsed at the boundary; verbose export text is not the canonical stored form.

## Privacy And Safety

- Publication requires an explicit confirmation that the route will be visible to everyone.
- Before publication, the server removes timestamps and trims approximately 150 meters from each end of routes longer than 600 meters.
- The client previews the public geometry returned by the server rather than assuming the complete private activity track was published.
- Community APIs expose creator profile attribution but not the source activity ID.
- Route discovery must not imply that a creator is currently present on the route.
- Configurable home/work privacy zones remain required before offering more precise public sharing controls.

## Backend Model

- `Route` owns public geometry, owner, source activity, activity type, visibility, status, bounds, distance, elevation, shape, and aggregate counts.
- `RouteBookmark` associates one user with one canonical route.
- `sourceActivityId` is unique and owner-verified at publication time.
- Visibility supports `public`, `unlisted`, or `private`; current creation always writes `public`.
- Status supports soft removal so bookmarks can disappear without corrupting historical activity data.

Primary API:

```text
POST   /v1/routes/from-activity/:activityId
GET    /v1/routes/nearby?latitude=&longitude=&radiusKm=
GET    /v1/routes/search?q=
GET    /v1/routes/mine
GET    /v1/routes/:id
PATCH  /v1/routes/:id
DELETE /v1/routes/:id
PUT    /v1/routes/:id/bookmark
DELETE /v1/routes/:id/bookmark
```

Nearby search initially uses indexed start coordinates and a bounded latitude/longitude window, then sorts by exact haversine distance. PostGIS is the scale-up path.

## iOS Boundaries

- `CommunityRouteStore` owns discovery, owned/bookmarked routes, publishing, bookmarking, and offline display state.
- `CommunityRoute` is the share-safe API contract and contains no activity timestamp data.
- `PreparedRoute` represents a selected community route or locally imported GPX/GeoJSON route.
- `SessionIntent` carries optional prepared route geometry independently from `ActivityRecorder.trackPoints`.
- `LiveMapView` draws the planned route behind the actual recorded trail. The recorder never treats planned geometry as completed activity data.
- Live route guidance frames the selected route during the start countdown, follows the runner once recording begins, and shows plus speaks an off-route warning after a sustained deviation. It announces when the runner rejoins. Turn-by-turn directions remain separate work.

## Import Validation

- Accept GPX track/route points and GeoJSON LineString geometry.
- Reject invalid coordinates, unsupported geometry, and files with fewer than two valid points.
- Preserve point order and altitude when present.
- Derive distance/elevation summaries locally for preview.
- Imported routes stay device-local until represented by the user's own completed activity.

## Database Update

```sh
cd backend
npm run db:generate
npm run db:push -- --accept-data-loss
```
