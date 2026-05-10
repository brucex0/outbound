# Activity Detail Page

Open this when redesigning, polishing, or adding features to the activity detail view.

## Current Implementation

File: `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`

The current view is a Strava-style layered detail page:

1. **Full-screen route map** — backed by `MKMapView`, with pace-colored route segments and photo pins
2. **Draggable information sheet** — default split position, collapsed map-first position, and expanded full-info position
3. **Stats hero** — large distance plus compact time/pace/elevation/HR stats
4. **Collapsible elevation profile** — real altitude over distance, hidden when no per-point altitude exists
5. **Collapsible splits** — per-km/mile breakdown
6. **Route controls** — privacy badge + share/export menu
7. **Coach reflection** — full card with reflection title/body and optional nudge
8. **Photos** — horizontal story strip

Limitations vs Strava and category expectations:
- Share is in a menu, not a persistent bottom toolbar
- No comparison to previous activities
- No mood/training context tags

## Strava Comparison

Strava's activity detail (iOS + web) uses:
- Full-width interactive hero map (~40% of viewport)
- Elevation profile below map
- Large primary stat (distance) + compact secondary stats
- Collapsible splits section (per-km/mile)
- Photos at GPS locations on map
- Fixed bottom action toolbar (kudos, comment, share, more)
- Social proof (kudos count, comments)
- Relative effort / heart rate zone chart

Outbound differentiators to lean into:
- Coach reflection with persona, narrative, and "what's next"
- Emotion-first framing (mood tags, comeback/momentum context)
- Training plan integration (this was part of Week X)
- Camera-native photo storytelling

## Phased Rollout

### Phase 1 — High Polish (current implementation target)

1. **Interactive map** — remove `.disabled(true)`, add tap to expand to full-screen map sheet
2. **Elevation profile chart** — Swift Charts bar/area chart below the map
3. **Pace-heatmap-colored polyline** — color route segments by pace
4. **Splits section** — collapsible per-km/mile breakdown with pace, time, elevation, HR
5. **Coach hero card** — full card with persona avatar, title, body, "What's next" CTA
6. **Floating bottom toolbar** — share, export, edit, delete in a frosted-glass toolbar
7. **Photo map pins** — small photo thumbnails on the map at GPS coordinates

### Phase 2 — Table Stakes

8. **Splits chart** — bar chart visualization of pace per segment
9. **Comparison to previous** — "You were X faster than last run on this route"
10. **Best effort badges** — "Best mile in 3 months", "Longest run this year"

### Phase 3 — Differentiation

11. **Coach narrative summary** — AI-generated prose about the run
12. **Training plan context** — "This was your long run for Week 3"
13. **Squad/Rival social reactions** — compact social strip
14. **Mood tags** — "Cruise Run", "Hill Crusher", "Recovery Jog"

## Component Architecture

The redesigned view uses these helper components:

- `ElevationProfileView` — Swift Charts area chart showing elevation over distance
- `PaceHeatmapPolyline` — segmented polyline colored by pace bands
- `SplitsSectionView` — collapsible per-km/mile split list
- `CoachHeroCard` — persona avatar + reflection title/body + next-action CTA
- `ActivityBottomToolbar` — floating frosted-glass toolbar with share/export/edit/delete
- `MapPhotoAnnotation` — photo thumbnail overlay on map at GPS coordinate
- `FullScreenMapView` — modal sheet with full interactive map

## Data Model Gaps

### Current `SavedRoutePoint`

```swift
struct SavedRoutePoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let verticalAccuracy: Double?
}
```

Saved route points persist altitude for newly saved activities so the elevation chart can plot a real profile instead of deriving shape from total gain.

### Decision for Phase 1

Use actual `SavedRoutePoint.altitude` values over cumulative route distance. The detail view hides the elevation profile when an activity has no per-point altitude data, rather than fabricating a smooth line from total `elevationGainM`.

### Splits Computation

Splits are computed on-the-fly by iterating route points, computing cumulative distance (haversine), and grouping into km/mile buckets. No model changes needed — `SavedRoutePoint` already has timestamps.

## Backend Impact

No backend changes required for Phase 1. All features are computed locally:

- **Elevation profile** — computed from persisted `SavedRoutePoint.altitude` values
- **Splits** — computed from route points via haversine + timestamp arithmetic
- **Pace heatmap** — computed from point-to-point distance/time deltas
- **Photo map pins** — use existing `SavedPhoto.coordinate`
- **Coach hero card** — use existing `SavedActivity.reflection`
- **Bottom toolbar** — use existing `ActivityStore.exportRoute()`

Future phases needing backend:
- **Comparison to previous on same route** — needs route similarity matching (server-side or local)
- **Training plan context** — needs `PlanState` from backend `GET /v1/planning/state`
- **Social reactions** — needs feed/reaction endpoints

## Files

- `ios/Outbound/Outbound/Activity/ActivityDetailView.swift` — main detail view
- `ios/Outbound/Outbound/Core/LocalActivityStore.swift` — `SavedActivity`, `SavedRoutePoint`, `RouteExportFormat`
- `ios/Outbound/Outbound/Activity/ActivityStore.swift` — `exportRoute()`

## Layout Decisions (Revised Per UX Feedback)

The layout uses a persistent full-screen route map with a bottom information sheet:

1. **Collapsed detent** — compact summary row, full-screen route map visible
2. **Split detent** — default opening state, route fit above the sheet and key information visible
3. **Expanded detent** — information sheet fills the screen and its content becomes scrollable
4. **Map refit** — route is fit with dynamic bottom padding based on the current sheet height
5. **Sheet gesture** — drag predicts the end height and snaps to the nearest detent with `.snappy`
6. **Content order** — stats, elevation, splits, route controls, coach card, photos

Safe-area strategy:
- The map ignores container safe areas so it feels full screen.
- The sheet owns bottom padding for the persistent app chrome.
- Route controls are inline in the sheet content, not a floating toolbar.
