# App Store Screenshots

The latest recapture package is `current/`, captured October 22, 2026 from
commit `c48df00e` plus simulator-only capture routing. Use `current/framed/`
in filename order for the updated English review set; `current/raw/` retains
unaltered 1320 × 2868 source captures. Framed exports are opaque 1284 × 2778
PNGs and preserve source aspect ratios and full screen contents.

The live-sharing image now shows the **follower's view of Sage Runner's active
run**, including the map marker, distance, time, current pace, heart rate, and
voice Cheer control. It replaces the empty trusted-contact setup concept in the
new set. It does not claim a real person joined a real session.

All participants, activities, locations, and stats are synthetic. Captures use the
current Debug production views, not a Release acceptance run. Raw Records is
retained for QA only: its sparse three-point fixture produces implausible best
efforts and no race predictions, so it is excluded from the composed set. Older
plan, Circle, and race-planning images below are legacy references and are not
part of the refreshed package. No assets were uploaded or published.

Rebuild/install from the current checkout, then capture without XCTest:

```sh
SIMULATOR_ID=4C2C54CB-2E70-45A4-AE9B-A59E940AD862 \
  ./scripts/build-install-bruce-main.sh --simulator --with-social
SIMULATOR_ID=4C2C54CB-2E70-45A4-AE9B-A59E940AD862 \
  ./scripts/capture-app-store-screenshots.sh
swift -module-cache-path /tmp/plainstride-screenshot-module-cache \
  scripts/generate-app-store-framed-screenshots.swift --current
```

Use an iPhone 17 Pro Max simulator with the current app installed. The capture
script sets a synthetic Golden Gate Park location, uses a loopback API override,
disables Firebase, dismisses discovery tips through launch defaults, and clears
only this simulator app's recording/photo journals on each explicitly seeded
capture launch. Use a dedicated capture simulator if it contains valuable data.
Allow MapKit tiles to load; increase `CAPTURE_SETTLE_SECONDS` above 12 if needed.
Inspect every image before upload. Screenshot routing compiles only for Debug
simulator builds, and production analytics behavior is unchanged.

Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
accept both source and framed dimensions (checked October 22, 2026).

## Previous Light And Dark Retake Set

1. `01-today-light.png` and `01-today-dark.png` — current Today workout and Circle progress
2. `03-live-redmond-half-light.png` and `03-live-redmond-half-dark.png` — Redmond Harvest half-marathon GPX simulation at 45:00 and 41% route progress
3. `06-social-light.png` and `06-social-dark.png` — connection request, Circle progress, milestone, and upcoming-run state
4. `07-ai-planned-workout-light.png` and `07-ai-planned-workout-dark.png` — expanded assistant explanation for the planned workout
5. `10-activity-detail-photos-light.png` and `10-activity-detail-photos-dark.png` — route detail with three existing running photos
6. `19-progress-records-light.png` — current Progress Records tab used for the AI-powered deep-insights slide

These captures use the current locally built Debug app with Social enabled. The
live-run pair uses the Debug-only Redmond Harvest route simulator derived from
the supplied half-marathon GPX data; it does not use the static seeded 10K
fixture. The activity-detail pair uses the existing coastal-trail, waterfront,
and park-after-rain photo assets attached to the Active Runner activity in the
temporary simulator data.

## Recommended Priority Set

Use these ten current, visually demonstrable concepts in this order. Marketing
headlines can be added during final App Store composition.

1. `01-today-dark.png` — know what to run today
2. `07-ai-planned-workout-dark.png` — understand and adapt today's workout
3. `19-progress-records-light.png` — AI-powered insights across best efforts, PR history, and race predictions
4. `05-cheer-live-track-dark.png` — private Live Track and voice cheers
5. `03-live-redmond-half-dark.png` — follow a route while recording
6. `10-activity-detail-photos-dark.png` — remember the run with route, stats, and moments
7. `18-circle-detail-progress-light.png` — stay consistent with a trusted Circle
8. `06-social-dark.png` — connect, celebrate, and plan together
9. `17-race-planning-light.png` — plan a race from recent training
10. `09-more-plans-dg.png` — choose a reviewed training plan

`04-progress-dark.png` and `05-cheer-live-track-dark.png` were freshly captured
from the current Debug app on September 7, 2026. The route-library screen is not
included because the deterministic Social Runner currently has no published or
bookmarked routes; the live route-guidance capture communicates the feature more
clearly and truthfully.

## Legacy Capture Set

1. `01-today-dark-gold.png` — testing-account Today overview and current recommendation
2. `02-adaptive-workout-dark-gold.png` — personalized comfortable-run rationale
3. `03-live-10k-dark-gold.png` — realistic live 10K progression with route and performance metrics
4. `04-progress-dark-gold.png` — Social Runner profile, learned duration, and weekly progress
5. `05-group-run-details-dark-gold.png` — group-run logistics, attendance, and training fit
6. `06-social-dark-gold.png` — connection request, upcoming group run, and social highlights
7. `07-ai-companion-dark-gold.png` — personalized explanation using readiness and recent load
8. `08-appearance-light-theme-gallery.png` — light mode and the configurable theme gallery
9. `09-more-plans-dg.png` — reviewed and curated plans available to the testing account
10. `10-activity-photo.png` — activity detail and shareable activity photo
11. `11-fresh-today-light.png` — fresh Today capture from the Social Runner simulator session (light appearance)
12. `today-light-app-store.png` — manually captured Today screen resized for App Store submission
12. `12-fresh-today-dark.png` — fresh Today capture from the Social Runner simulator session (dark appearance)
13. `13-cheer-me-on-dark.png` — live Cheer invitation picker with a seeded connection (dark appearance)
14. `14-race-planning-dark.png` — history-backed half-marathon recommendation (dark appearance)
15. `15-circle-detail-progress-dark.png` — seeded Circle weekly and member progress (dark appearance)
16. `16-cheer-me-on-light.png` — live Cheer invitation picker with a seeded connection (light appearance)
17. `17-race-planning-light.png` — history-backed half-marathon recommendation (light appearance)
18. `18-circle-detail-progress-light.png` — seeded Circle weekly and member progress (light appearance)

The legacy screenshots were captured from the Debug-only Social Runner testing account
backed by the local API's deterministic persona seed. Release builds do not expose
testing personas or activate recording fixtures. The older `dark-gold` filename
suffixes are retained so existing App Store upload references remain stable.

The Circle captures use the Debug-only UI fixture so the same 3-of-7 weekly progress,
member targets, recent activities, and Cheer are reproducible without a live account.

## Fresh Capture Workflow

1. Build and launch the Debug app with the deterministic Social Runner persona:

   ```sh
   ./scripts/build-install-bruce-main.sh --simulator --launch --with-test-personas --with-social
   ```

2. Capture the currently displayed screen from the booted simulator. Use `--mask=black` so the PNG has no alpha channel:

   ```sh
   xcrun simctl io <SIMULATOR_ID> screenshot --mask=black /tmp/plainstride.png
   ```

3. Resize the simulator capture to the App Store dimensions and copy it into this directory:

   ```sh
   sips -z 2778 1284 /tmp/plainstride.png --out artifacts/app-store-screenshots/<name>.png
   ```

4. Verify every upload candidate is `1284 × 2778` with `hasAlpha: no` before uploading.
