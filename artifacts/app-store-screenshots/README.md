# App Store Screenshots

Upload these iPhone screenshots in filename order. Each PNG is 1284 × 2778
pixels with no alpha channel, matching an App Store Connect-supported size.

## Latest Light And Dark Retake Set

1. `01-today-light.png` and `01-today-dark.png` — current Today workout and Circle progress
2. `03-live-redmond-half-light.png` and `03-live-redmond-half-dark.png` — Redmond Harvest half-marathon GPX simulation at 45:00 and 41% route progress
3. `06-social-light.png` and `06-social-dark.png` — connection request, Circle progress, milestone, and upcoming-run state
4. `07-ai-planned-workout-light.png` and `07-ai-planned-workout-dark.png` — expanded assistant explanation for the planned workout
5. `10-activity-detail-photos-light.png` and `10-activity-detail-photos-dark.png` — route detail with three existing running photos

These captures use the current locally built Debug app with Social enabled. The
live-run pair uses the Debug-only Redmond Harvest route simulator derived from
the supplied half-marathon GPX data; it does not use the static seeded 10K
fixture. The activity-detail pair uses the existing coastal-trail, waterfront,
and park-after-rain photo assets attached to the Active Runner activity in the
temporary simulator data.

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
