# Activity Detail Page

Open this when redesigning, polishing, or adding features to the activity detail view.

## Current Implementation

Authoritative file: `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`

Android counterpart: `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt`, with its parity inventory in `android/feature/activity/IOS_PARITY.md`.

My Activities and other local activity consumers receive activities ordered by `startedAt` descending, so the newest activity is always first, including after imports, sync restoration, and date edits.
The history screen supports swipe-to-delete for one activity and selection mode for deleting multiple activities after a destructive confirmation.

The current view is a Strava-style layered detail page:

1. **Full-screen route map** — backed by `MKMapView`, with pace-colored route segments and photo pins
2. **Draggable information sheet** — default split position, collapsed map-first position, and expanded full-info position
3. **Stats hero** — large distance plus compact time/pace/elevation/HR stats and, when the inputs are reliable, a calculated calorie estimate based on activity type, distance-derived speed, duration, and the runner's latest weight
4. **Collapsible elevation profile** — terrain-corrected altitude over distance for newly recorded authenticated outdoor activities, with provider attribution; raw device altitude remains the offline/signed-out fallback, and the section is hidden when no per-point altitude exists
5. **Collapsible splits** — per-km/mile breakdown
6. **Route actions** — persistent navigation-bar Share action; visible owner-only `Save Route` top-bar action for activities with usable track geometry; GPX and GeoJSON exports remain implemented internally but are hidden from the current UI
7. **Guide reflection** — full card with reflection title/body and optional nudge
8. **Photos** — a permanent horizontal strip in the sheet selects GPS-tagged map pins; tapping the selected photo opens a full-screen lightbox with paging, caption, and counter

Social activity posts reuse this same map-and-sheet detail shell through a share-safe activity adapter. The Social presentation adds the connection header, caption, inline Cheer/comment actions, contextual companion feedback, and a medium-to-full-height comment drawer with a sticky composer. The share-safe activity summary carries the owner's stored elevation gain and calorie total, and route altitude samples preserve the shared elevation profile; Social never recalculates another runner's calories from the viewer's private weight. Ownership gates editing and route publication: `Save Route` remains available on the current runner's own Social posts but is omitted from another runner's activity. Unavailable private source/gear metadata and route privacy are omitted.

The full Social activity card opens activity detail when tapped, while its profile, overflow, Cheer, and Comments controls retain their dedicated actions. Card-driven detail opens emit `activity_detail_opened` with `source_type=social_feed` on both clients.

The Android stored-activity detail now follows the same map-first hierarchy: an interactive full-screen Google map, pace-colored route segments with pause gaps, GPS photo pins, a draggable collapsed/split/expanded information sheet, two-column stats, a horizontal photo strip and lightbox, collapsible elevation and split sections, private metadata, and the companion reflection. It derives split/elevation values from route points, follows the saved metric/imperial preference on-screen and in the share card, and hides GPX/GeoJSON export from the current UI. Android-specific remaining work is recorded in its parity manifest rather than treated as an implicit platform exception.

Connection photos are delivered in the visible social-post payload as ordered metadata plus 15-minute signed read URLs. Storage keys never cross the social response boundary. The iOS adapter maps those records into the shared photo-strip model, and the shared image view supports both local file URLs and signed HTTPS media.

The Share Activity Card action renders a 9:16 image built from a full-bleed, high-resolution standard `MKMapSnapshotter` route screenshot with points of interest, buildings, and the recorded route drawn over it, plus key stats overlaid in a Strava-style lower gradient. The activity title receives the full content width above the bottom row so typical titles remain on one line; the two-column stats stay at bottom-left while the QR and branding sit at bottom-right. Stats use single-line value/unit pairs and title-case labels so distance and pace units never wrap onto a separate line. The QR contains a scannable canonical referral URL that opens an installed app or offers the appropriate App Store, Play Store, iOS beta, and Android beta destinations configured on the backend. Rendering opens a full-card preview first, with a dedicated Save Image action that writes to Photos and a separate Share action that presents the system Share Sheet with only the image. If referral creation is unavailable, the QR code uses the stable `https://plainstride.ai/invite` landing link; if a route snapshot cannot be created, rendering falls back to a stats-only card so sharing still succeeds.

Limitations vs Strava and category expectations:
- Share is persistent in the navigation bar rather than a fixed bottom social toolbar
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
- Guide reflection with persona, narrative, and "what's next"
- Emotion-first framing (mood tags, comeback/momentum context)
- Training plan integration (this was part of Week X)
- Camera-native photo storytelling

## Phased Rollout

### Phase 1 — High Polish (current implementation target)

1. **Interactive map** — remove `.disabled(true)`, add tap to expand to full-screen map sheet
2. **Elevation profile chart** — Swift Charts bar/area chart below the map
3. **Pace-heatmap-colored polyline** — color route segments by pace
4. **Splits section** — collapsible per-km/mile breakdown with pace, time, elevation, HR
5. **Guide hero card** — full card with persona avatar, title, body, "What's next" CTA
6. **Floating bottom toolbar** — share, export, edit, delete in a frosted-glass toolbar
7. **Photo map pins** — small photo thumbnails on the map at GPS coordinates

### Phase 2 — Table Stakes

8. **Splits chart** — bar chart visualization of pace per segment
9. **Comparison to previous** — "You were X faster than last run on this route"
10. **Best effort badges** — "Best mile in 3 months", "Longest run this year"

### Phase 3 — Differentiation

11. **Guide narrative summary** — AI-generated prose about the run
12. **Training plan context** — "This was your long run for Week 3"
13. **Squad/Rival social reactions** — compact social strip
14. **Mood tags** — "Cruise Run", "Hill Crusher", "Recovery Jog"

## Component Architecture

The redesigned view uses these helper components:

- `ElevationProfileView` — Swift Charts area chart showing elevation over distance
- `PaceHeatmapPolyline` — segmented polyline colored by pace bands
- `SplitsSectionView` — collapsible per-km/mile split list
- `GuideHeroCard` — persona avatar + reflection title/body + next-action CTA
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

Use actual `SavedRoutePoint.altitude` values over cumulative route distance. Before save, iOS samples the recorded track to at most 450 points and requests authenticated terrain correction from `POST /v1/elevation/correct`. The backend bilinearly samples global zoom-14 Mapzen terrain tiles, applies segment-local median and weighted smoothing, and counts only climbs with at least 10 m prominence. The corrected points, gain, algorithm version, and attribution metadata are stored with the local activity. Previously saved Plainstride outdoor activities without correction metadata are lazily corrected when their owner opens activity detail, then marked for backend resync. If authentication, connectivity, or the provider is unavailable, save and activity detail remain local-first and preserve the on-device 10 m prominence result. The detail view hides the elevation profile when an activity has no per-point altitude data rather than fabricating a profile from total gain.

### Splits Computation

Splits are computed on-the-fly by iterating route-point edges and allocating their distance and active time into exact km/mile buckets. Edges that end at a `startsNewSegment` point are pause/resume gaps, so their timestamp and apparent map distance are excluded. This keeps split totals aligned with the saved moving time instead of elapsed wall-clock time. No model changes are needed because `SavedRoutePoint` already has timestamps and segment boundaries.

## Backend Impact

Most analysis features are computed locally:

- **Calories** — calculated on demand for the runner's private activity surfaces from current activity facts and the latest private weight, using speed-banded MET values from the [2024 Adult Compendium of Physical Activities](https://pacompendium.com/adult-compendium/), so workout or weight edits update those completed-workout surfaces without persisting a stale value; hidden when weight, distance, duration, or speed plausibility is insufficient. Social detail displays only the owner's stored calorie total from the share-safe activity response.
- **Elevation profile** — computed from persisted `SavedRoutePoint.altitude` values; corrected routes disclose Mapzen and source-agency attribution
- **Splits** — computed from route points via haversine + timestamp arithmetic
- **Pace heatmap** — computed from point-to-point distance/time deltas
- **Photo map pins** — use existing `SavedPhoto.coordinate`
- **Guide hero card** — use existing `SavedActivity.reflection`
- **Bottom toolbar** — use existing `ActivityStore.exportRoute()`

Social activity photos require the backend Social response to select post activity photos and issue short-lived signed media URLs for authorized viewers.

Future phases needing backend:
- **Comparison to previous on same route** — needs route similarity matching (server-side or local)
- **Training plan context** — needs `PlanState` from backend `GET /v1/planning/state`
- **Social reactions** — needs feed/reaction endpoints

## Files

- `ios/Outbound/Outbound/Activity/ActivityDetailView.swift` — main detail view
- `ios/Outbound/Outbound/Core/LocalActivityStore.swift` — `SavedActivity`, `SavedRoutePoint`, `RouteExportFormat`
- `ios/Outbound/Outbound/Activity/ActivityStore.swift` — `exportRoute()`
- `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt` — stored-activity map, sheet, stats, photos, elevation, splits, and metadata
- `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityViewModel.kt` — mutations, share-card rendering, and analytics
- `android/feature/activity/IOS_PARITY.md` — Android parity inventory, reference scenarios, and remaining gaps

## Layout Decisions (Revised Per UX Feedback)

The layout uses a persistent full-screen route map with a bottom information sheet:

1. **Collapsed detent** — compact summary row, full-screen route map visible
2. **Split detent** — default opening state, route fit above the sheet and key information visible
3. **Expanded detent** — information sheet fills the available screen below the status bar and its content becomes scrollable
4. **Map refit** — route is fit with dynamic bottom padding based on the current sheet height
5. **Sheet gesture** — drag predicts the end height and snaps to the nearest detent with `.snappy`
6. **Content order** — stats, elevation, splits, activity metadata when relevant, guide card
7. **Media layout** — the route map remains the full-screen background without a floating thumbnail; the sheet owns a horizontal photo strip, the active photo drives the selected map annotation, and a second tap opens the immersive lightbox
8. **Photo editing** — Edit Activity opens the same take/delete/reorder photo manager used after finishing an activity. The map initially selects the first GPS-tagged photo so its pin is visible; photos without an available coordinate remain saved but do not produce a misleading pin.
9. **Readability** — the sheet uses an opaque system background so map colors do not wash out text or chart labels
10. **Disclosure animations** — inline sections such as elevation and splits fade in place rather than sliding over nearby content
11. **Stats layout** — activity title plus a two-column Strava-style metric grid: Distance, Avg Pace, Moving Time, Elev Gain, and available extras
12. **Splits layout** — Strava-style table with distance index, pace-as-time, proportional blue bar, and optional elevation delta; do not show a separate time column
13. **Persistent actions** — keep Share and Edit visible beside each other in the trailing navigation bar at every sheet detent

Safe-area strategy:
- The map ignores container safe areas so it feels full screen.
- The sheet ignores the bottom safe area but stays below the status bar when expanded.
- The sheet owns bottom padding for the persistent app chrome.
- Route controls are inline in the sheet content, not a floating toolbar.
