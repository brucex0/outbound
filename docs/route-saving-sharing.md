# Route Saving And Sharing Requirements

Open this when implementing saved routes, route export, route sharing, or route storage policies.

## Product Goals

- Save route data as real GPS points, not only as a screenshot or preview image.
- Let users export and share recorded routes from activity detail.
- Let route storage remain lightweight enough for long workouts such as marathon-length runs.
- Preserve a future path toward friend/public route sharing if backend support is added later.

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
- Route-related UX should live on saved activity detail rather than in a separate saved-routes library for V1.
- Opening an activity with route data should show a full map plus route-related activity details.

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
- Use that stored route as the canonical source for in-app map rendering and sharing.
- Export standard share formats only when requested.
- Keep route UI attached to activity detail first, then add broader sharing surfaces later if product needs it.

## Current V1 Implementation

- Saving an activity also saves the simplified canonical route needed for in-app route rendering.
- The post-run save flow does not expose a separate route toggle because saved activity detail depends on persisted route data.
- Route export lives on saved activity detail and supports on-demand `GPX` and `GeoJSON` export through the iOS share sheet.
- The Me/Profile screen focuses on `My Activities` rather than a separate saved-routes library.
- Older saved activities that only contain raw `trackPoints` are upgraded at read time into the canonical route model.
