# Activity Detail Page

Open this when redesigning, polishing, or adding features to the activity detail view.

## Current Implementation

Authoritative file: `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`

Android counterpart: `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt`, with its parity inventory in `android/feature/activity/IOS_PARITY.md`.

My Activities and other local activity consumers receive activities ordered by `startedAt` descending, so the newest activity is always first, including after imports, sync restoration, and date edits.
The history screen supports swipe-to-delete for one activity and selection mode for deleting multiple activities after a destructive confirmation. Stored activity detail also exposes a confirmed Delete action in the navigation bar.
Live and saved average pace use the same sport-specific plausibility bounds: at least 4:00/km for walking and 3:20/km for hiking, with separate bounds for running and cycling. Out-of-range pace is hidden as unavailable while the recorded distance, duration, and route remain intact.

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

The full Social activity card opens activity detail when tapped, while its profile, overflow, Cheer, and Comments controls retain their dedicated actions. Card-driven detail opens emit `activity_detail_opened` with `source_type=social_feed` on both clients. The feed card shows up to two compact activity milestones, followed by a count when there are more. Social activity detail shows up to three compact milestone rows, followed by a count when needed; accepted connections receive only awards whose backend `shareEligible` flag is true, while an owner can see their own private milestone awards.

The Android stored-activity detail now follows the same map-first hierarchy: an interactive full-screen Google map, pace-colored route segments with pause gaps, photo pins from valid embedded GPS or the nearest route sample by capture time, a draggable collapsed/split/expanded information sheet, two-column stats, a horizontal photo strip and lightbox, collapsible elevation and split sections, private metadata, and the companion reflection. It derives split/elevation values from route points, follows the saved metric/imperial preference on-screen and in the share card, and hides GPX/GeoJSON export from the current UI. Android-specific remaining work is recorded in its parity manifest rather than treated as an implicit platform exception.

Connection photos are delivered in the visible social-post payload as ordered metadata plus 15-minute signed read URLs. Storage keys never cross the social response boundary. Android uploads locally saved JPEGs and their capture metadata after the activity sync succeeds, then retains the private local file reference alongside the returned remote photo ID so the detail view works offline. The iOS adapter maps those records into the shared photo-strip model, and the shared image view supports both local file URLs and signed HTTPS media.

The Share Activity Card action renders a 9:16 image built from a full-bleed, high-resolution standard `MKMapSnapshotter` route screenshot with points of interest, buildings, and the recorded route drawn over it, including 144-pixel circular photo thumbnails at valid, visible photo coordinates using the same local/remote cache as the detail map (unavailable images are skipped), plus key stats overlaid in a Strava-style lower gradient. The activity title receives the full content width above the bottom row so typical titles remain on one line; the two-column stats stay at bottom-left while the QR and branding sit at bottom-right. Stats use single-line value/unit pairs and title-case labels so distance and pace units never wrap onto a separate line. The QR contains a scannable canonical referral URL that opens an installed app or offers the appropriate App Store, Play Store, iOS beta, and Android beta destinations configured on the backend. Rendering opens a full-card preview first, with a dedicated Save Image action that writes to Photos and a separate Share action that presents the system Share Sheet with only the image. If referral creation is unavailable, the QR code uses the stable `https://plainstride.ai/invite` landing link; if a route snapshot cannot be created, rendering falls back to a stats-only card so sharing still succeeds.

Limitations vs Strava and category expectations:
- Share is persistent in the navigation bar rather than a fixed bottom social toolbar
- No comparison to previous activities
- No mood/training context tags

## Activity editor

- The editor groups activity identity, photos, workout metrics, and gear, with a persistent Save Changes action and discard confirmation.
- Save review and edit share `ActivityPhotoReviewSection`: camera/library actions, tap to preview, long press to select, delete selection, and drag selected photos to reorder. The top route/photo pager remains specific to save review.
- Edit keeps existing file/remote photo references and new captures/imports in one ordered draft. Save Changes persists the photo draft; Cancel discards it. Existing images are not decoded and re-encoded for metadata edits or reordering.
- New imports retain the existing EXIF-aware importer and activity placement logic. Saved previews use the existing cached image/zoom view; newly added photos use their in-memory image.
- Mixed saved/new ordering is passed to photo persistence as a validated permutation of retained photos followed by new captures. The default remains append-only for other callers.
- Metadata and photo persistence are sequential: if photo saving fails after metadata succeeds, the editor retains the draft for retry; it does not roll metadata back.
- Distance follows the measurement preference with a permanent unit suffix and locale-aware decimals. Unchanged displayed distance preserves exact stored meters. Duration uses labeled hours/minutes/seconds; totals edits retain route/split samples.
- Manual checks still required: save-page gesture parity; edit preview, selection, delete, mixed-photo reorder, camera/library import, Cancel, failed save/retry, reopen, and Photos album export enabled/disabled. Cover local/cached/remote images and rotated/mirrored imports.

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

Use actual `SavedRoutePoint.altitude` values over cumulative route distance. Before save, iOS samples each segment at equal distance intervals (20 m minimum, increased to fit 450 points), retains both segment endpoints, and requests authenticated terrain correction from `POST /v1/elevation/correct`.

`terrain-v2` samples terrain along that geometry every 20 m, up to 20,000 internal samples and 96 terrain tiles. It applies a three-sample median and a distance-weighted 40 m-radius smoother independently per segment, preserving endpoint heights. A directional valley/peak accumulator counts climbs reaching 3 m and waits for a 3 m descent before closing a climb; downhill-only profiles cannot create ascent. The API interpolates the smoothed heights back onto the requested points and reports gain from the internal profile. This is an estimate: the 3 m policy is a conservative small-climb choice, not a guarantee that all 3 m changes are terrain rather than map error. Sparse route geometry cannot recover trail bends or bridge heights absent from the terrain model.

Corrected points, gain, version, and attribution are saved locally. Opening an owner’s outdoor Plainstride activity upgrades missing or `terrain-v1` correction and marks it for backend resync. The client requires `terrain-v2` responses before marking an upgrade complete, so an older server leaves existing data intact and retries on a later open. Offline/provider failures preserve the last result. Deploy the backend before releasing this iOS version; no database reset or migration is required.

New saves retain the full available pre-correction route locally in `route.original.bin`; first-time enrichment of an older uncorrected route retains its existing samples there. This sidecar is never uploaded/shared and is removed with the activity directory. Previously corrected activities cannot recover original phone altitude that was already overwritten. Live/offline GPS retains its conservative 10 m threshold and accuracy/spike filters, with the same directional climb logic. Barometer capture remains future work.

The profile is hidden when no per-point altitude exists. Current verification covers synthetic flat/noisy/rolling/steep/downhill/segmented profiles and sampling-density comparisons; controlled routes with independently measured ascent remain necessary before claiming absolute accuracy.

Android uses the same `terrain-v2` endpoint and version-refresh policy. Its Room metadata and upload/restore models retain correction attribution/version. Android keeps full saved geometry and interpolates returned heights onto its original points; original altitude is retained separately in a local-only Room table. Local save does not wait for correction, and sync gives enrichment a bounded budget before uploading the last available result. See `android/feature/recording/IOS_PARITY.md` for Android storage/reset details.

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
- `ios/Outbound/Outbound/Core/ActivityPhotoCache.swift` — saved-photo render-URL cache, thumbnail variants, upload mapping
- `ios/Outbound/Outbound/Activity/ActivityStore.swift` — `exportRoute()`
- `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt` — stored-activity map, sheet, stats, photos, elevation, splits, and metadata
- `android/feature/activity/src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityViewModel.kt` — mutations, share-card rendering, and analytics
- `android/feature/activity/IOS_PARITY.md` — Android parity inventory, reference scenarios, and remaining gaps

## Layout Decisions (Revised Per UX Feedback)

The layout uses a persistent full-screen route map with a bottom information sheet:

1. **Collapsed detent** — compact summary row, full-screen route map visible
2. **Split detent** — default opening state, route fit above the sheet and key information visible
3. **Expanded detent** — information sheet fills the available screen below the status bar and its content becomes scrollable
4. **Map refit** — route is fit with dynamic bottom padding based on the current sheet height and extra edge clearance, preserving a visible route viewport as the sheet moves
5. **Sheet gesture** — drag predicts the end height and snaps to the nearest detent with `.snappy`
6. **Content order** — stats, elevation, splits, activity metadata when relevant, guide card
7. **Media layout** — the route map remains the full-screen background without a floating thumbnail; the sheet owns a horizontal photo strip, the active photo drives the selected map annotation, and a second tap opens the immersive lightbox
8. **Photo interaction and editing** — Edit Activity opens the same take/delete/reorder photo manager used after finishing an activity, and both surfaces import from the photo library. Imported photos keep their EXIF capture time and, when it sits close to the recorded route, their GPS location; the capture time places the photo at the matching distance along the route, while GPS beyond a 500 m plausibility radius is discarded so a photo taken elsewhere never produces a misleading map pin. Imports are downsampled to a 2048 px longest edge before storage. PhotosPicker needs no photo-library permission. The map initially selects the first GPS-tagged photo so its pin is visible; photos without an available coordinate remain saved but do not produce a misleading pin. Tapping a photo pin opens that photo in the lightbox and synchronizes the selected carousel thumbnail. The lightbox supports paging, pinch-to-zoom, panning while zoomed, and double-tap zoom/reset.
9. **Photo rendering and caching** — all saved-photo surfaces (history/feed thumbnails, detail carousel, map pins, lightbox) resolve URLs through `ActivityPhotoCache` (`ios/Outbound/Outbound/Core/ActivityPhotoCache.swift`). The cache keys content by stable photo identity (remote photo id when present, otherwise the stored relative path) and maps identities to local files, so uploaded or restored photos keep rendering from disk instead of a freshly signed remote URL. Remote bytes are persisted into `Application Support/Outbound/PhotosCache`, thumbnail surfaces request downsampled decodes (`maxPixelSize`) so full-size camera JPEGs never inflate small views, and the identity-to-file mapping persists across launches via `PhotoCacheMappings.plist`.
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

## Photo Orientation Regression Guard

- Android activity-detail strip and lightbox share `ActivityPhotoDecoder.kt`, which applies all eight EXIF orientations (including mirroring) to full-resolution in-memory pixels before Compose renders or remembers them. Original JPEG bytes and metadata remain unchanged; reopening decodes the same stored bytes with the same transform. This rendering correction leaves the analytics contract unchanged and adds no image metadata to events.

- Full-size ImageIO decodes must transfer EXIF orientation to `UIImage`; thumbnail decodes already apply `kCGImageSourceCreateThumbnailWithTransform`. Never wrap untransformed camera pixels with the default `.up` orientation.
- Introduced by `015087c5` (2026-09-18): the shared cache replaced UIKit decoding with ImageIO, preserving orientation only for thumbnails. Upright-only fixtures and compile checks missed the visual mismatch.
- `ActivityPhotoCacheTests.fullSizeDecodePreservesEXIFOrientation` encodes all eight EXIF orientations and checks full-size, memory-cache, and thumbnail paths against UIKit decoding. Run it when tests are explicitly requested.
- Before shipping photo pipeline changes, compare EXIF-rotated portrait, landscape, and mirrored photos across feed, detail strip/map pin, and lightbox (including zoom, cold load, and cached reopen). Include local and remote media; verify orientation and aspect ratio agree. Already-normalized fixtures are insufficient.
- Existing `photo_previewed` and `photo_zoomed` instrumentation remains in the viewer; this decoding correction adds no event or photo metadata.

## Moving And Elapsed Time

- New phone-recorded outdoor Run, Walk, Hike, and Bike activities save moving seconds in the existing `durationSecs` field. `startedAt` / `endedAt` retain elapsed wall-clock time, including manual/automatic pauses; no third duration or backend/Room schema change is needed.
- Moving time excludes explicit pauses and confirmed stationary time while recording continues. Confirmation requires a 20-second cluster within 3 m of a fixed GPS anchor. A native speed lower bound (`speed − speedAccuracy`) above 0.65 m/s for runs, 0.35 m/s for walks/hikes, or 1.0 m/s for cycling cancels a stop candidate; accumulating displacement against the fixed anchor protects slow sustained movement. The confirmed interval is removed retrospectively, so the live duration can adjust when a stop is confirmed.
- Accounting uses each raw GPS observation’s timestamp before stationary route points are filtered out. Speed accuracy up to 3 m/s is accepted; missing/unreliable native speed falls back to the positional cluster. Position accuracy worse than 20 m, observation gaps over 30 seconds, and stops shorter than confirmation remain moving. Duplicate/out-of-order fixes are ignored. Recording requests updates without a distance minimum so stationary observations continue. Foreground timer frequency and delayed batched delivery do not define moving time. Outdoor device validation remains necessary, especially on slow technical climbs.
- Main duration and average pace use moving time. Cycling activity details and live/review metrics show speed; its completed average is distance divided by moving time. Detail/review also show Elapsed Time.
- Existing auto-pause controls, workout/coaching/goal clocks, cadence time axes, and route recording remain unchanged. Route-derived split/heatmap timing still uses route timestamps and explicit segment gaps; it is not a newly reconstructed per-split moving-time series.
- Confirmed stopped duration is checkpointed with active-session recovery. Unsaved-review recovery preserves the completion timestamp. Watch heart-rate reconciliation retains phone moving duration when a phone route exists.
- Existing activities, manual entries, imported activities, and standalone Watch/Wear recordings retain their supplied duration; this change does not infer historical moving time from sparse routes or add wearable stop detection.
- Existing sync already transmits `durationSecs`, `startedAt`, and `endedAt`; no backend deployment, data reset, or migration is required. Editing duration retains the existing edit semantics.
- Verification: Android phone Kotlin compile; iOS simulator build. No test suite run. Outdoor GPS behavior and real-device recovery remain manual acceptance checks before release.

### Stationary walk correction

- The first implementation required native speed accuracy at most 0.5 m/s and repeatedly sampled the latest fix from a UI timer. That could reject all stop evidence or lose it during background/sparse callbacks, leaving moving time equal to the recording timer.
- The observation-based correction also labels Social feed duration as Moving Time. It does not rewrite an existing activity from a screenshot: previously omitted stationary observations cannot establish a reliable corrected duration from the saved simplified route alone.

- Indoor launch explicitly disables GPS stop accounting, and this choice is retained in recovery state, so stationary treadmill sessions keep their unpaused timer duration.
