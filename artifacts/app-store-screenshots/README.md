# App Store Screenshots

Upload these iPhone screenshots in filename order. Each PNG is 1284 × 2778
pixels with no alpha channel, matching an App Store Connect-supported size.

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

The screenshots were captured from the Debug-only Social Runner testing account backed
by the local API's deterministic persona seed. The live 10K state uses the Debug-only
deterministic recording flag. Release builds do not expose testing personas or activate
the recording fixture. The older `dark-gold` filename suffixes are retained so existing
App Store upload references remain stable; the current captures use the light Victory
Gold appearance.

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
