# Route Saving And Sharing Requirements

Open this when implementing saved routes, route export, route sharing, or route storage policies.

## Product Goals

- Save route data as real GPS points, not only as a screenshot or preview image.
- Let users revisit saved routes inside the app from a saved-routes surface such as Profile.
- Let users share routes with friends or publicly in a future backend-enabled flow.
- Keep route storage efficient enough for long workouts such as marathon-length runs.

## Route Data Requirements

- A saved route must be an ordered list of valid GPS points that can be replotted as a map polyline.
- Each point must include at minimum:
  - `latitude`
  - `longitude`
  - `timestamp`
- Point order must be preserved exactly so route playback and plotting remain correct.
- Optional future fields such as `altitude`, `speed`, or `horizontalAccuracy` should be added only if they unlock a concrete product need.

## Saved Route Experience

- The app should save route data together with each saved activity.
- Users should be able to browse previously saved routes from the Me/Profile area.
- A saved-routes list should eventually show:
  - date or title
  - distance and duration
  - a small route preview
- Opening a saved route should show a full map plus route-related activity details.

## Sharing Requirements

- Each saved route should support share actions from inside the app.
- The route should be shareable as real route data in a standard format such as `GPX` or `GeoJSON`.
- A preview image or share card is optional and secondary to the canonical route data.
- Sharing modes should be modeled as:
  - `Private`
  - `Friends`
  - `Public`

## Sharing Scope Notes

- `Friends` and `Public` are valid product requirements even if backend support is not implemented yet.
- In the short term, the app can support local save plus external export/share flows.
- True friend-only and public sharing will eventually require backend storage, permissions, and share-link infrastructure.

## Storage Requirements

- Route storage must scale to long activities without saving unnecessary point density.
- The canonical saved route should be a compact native representation rather than a permanently stored verbose text export.
- `GPX` and `GeoJSON` should be generated on demand when the user exports or shares a route.
- The saved route must stay accurate enough for:
  - in-app route previews
  - full saved-route map rendering
  - export and sharing

## Simplification Rules

- Do not persist every raw GPS callback if it adds little visual or product value.
- Always keep the first and last point.
- Keep points when enough distance has elapsed since the last kept point.
- Keep points when enough time has elapsed since the last kept point.
- Keep meaningful turns so the route shape remains faithful.
- Drop redundant near-duplicate or nearly collinear points when they do not materially change the displayed route.

## Recommended V1 Direction

- Persist a simplified but map-accurate ordered route locally with `latitude`, `longitude`, and `timestamp`.
- Use that stored route as the canonical source for saved-route browsing and sharing.
- Export standard share formats only when requested.
- Build local saved-route UI first, then layer true friend/public sharing on top once backend support exists.

## Current V1 Implementation

- Saving an activity also saves the simplified canonical route needed for in-app route rendering.
- The post-run save flow no longer exposes a separate route toggle because saved activity detail depends on persisted route data.
- Route export lives on saved activity detail and supports on-demand `GPX` and `GeoJSON` export through the iOS share sheet.
- The Me/Profile screen focuses on `My Activities` rather than a separate saved-routes library.
- Older saved activities that only contain raw `trackPoints` are upgraded at read time into the canonical route model.
