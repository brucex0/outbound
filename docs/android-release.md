# Android Play Release

Open this for Play Console preparation, signed bundles, release policy, privacy review, performance profiles, or production rollback. This document does not authorize publishing.

## Production Rollout Policy

- Always publish Android production releases at **100%** across the configured countries. Do not use a staged rollout unless Bruce explicitly changes this instruction.
- Bruce confirmed on November 3, 2026 that Android has no users and manually changed version `1.0.3` (6) from 10% to 100%. This is the standing preference for future releases.
- In Play Console, set the rollout percentage to `100`. The publishing script's `completed` release status already represents a full rollout.

## Version And Signing Policy

- `PLAINSTRIDE_VERSION_CODE` is a monotonically increasing positive integer assigned by CI for every Play upload.
- `PLAINSTRIDE_VERSION_NAME` is the user-facing semantic version. A rollback build still receives a new version code.
- Enroll in Play App Signing and protect the upload key separately. Never commit a keystore or password.
- Keep local upload passwords in `~/.config/plainstride/android-upload.env` (mode `600`) or pass them through the environment; the publishing script does not access macOS Keychain. Never commit this file or a keystore.
- Supply `PLAINSTRIDE_MAPS_API_KEY` as a Gradle property from CI (`ORG_GRADLE_PROJECT_PLAINSTRIDE_MAPS_API_KEY`). Restrict it in Google Cloud to the release application ID and Play signing certificate. Missing keys render an accessible “Map unavailable” state and `verifyPlayReleaseConfiguration` fails closed.
- Supply `PLAINSTRIDE_SPOTIFY_CLIENT_ID` as a Gradle property only for builds whose Spotify dashboard allows the exact `com.plainstride.outbound://spotify-callback` redirect. Without it, Spotify authorization and playback stay disabled with a user-visible configuration state; no client secret is embedded in the app.
- Phone and Wear use the same CI-supplied version and upload-key variables, while remaining separate application IDs (`com.plainstride.outbound` and `com.plainstride.outbound.wear`). Ordinary `assembleRelease` remains unsigned when secrets are absent so source verification is reproducible. Each `bundleRelease` task depends on its fail-closed configuration check.

```sh
./gradlew :app:bundleRelease :wear:bundleRelease
```

## Reusable Play Publishing Script

From the repository root, build a signed phone bundle and publish it to the
existing Alpha closed-testing track with:

```sh
PLAINSTRIDE_VERSION_CODE=1 PLAINSTRIDE_VERSION_NAME=1.0 \
  ./scripts/publish-android-play.sh --track closed --publish
```

The script requires the Android Publisher API to be enabled and the Google
identity to have Play Console release access. Use the active `gcloud` account,
or set `PLAINSTRIDE_PLAY_SERVICE_ACCOUNT_JSON` to a protected service-account
key file. Service-account JSON is never stored in the repository; the script
uses an isolated temporary `gcloud` config for it. The script reads upload-key
passwords from `~/.config/plainstride/android-upload.env` or explicit environment
variables, builds and verifies the AAB, uploads it, validates the edit, and
commits the release. `closed` targets the default `alpha` track; `internal` and
`production` are also supported. Increase the version code for every upload.
Without `--publish`, the script only builds the signed AAB.

For an app that is still in Draft, Play only accepts a track release with
`draft` status. Upload and save it for owner review with
`--release-status draft`; then review and submit the release in Play Console.
The default `completed` status is for an app that has already left Draft.
The script prints Android Publisher error details when an API request fails.

Configure track countries and testers in Play Console before publishing a
closed-testing release. Play bundles also require the Maps, Google server
client, Firebase, and production Google RevenueCat Gradle properties described
in the release checks below.

Before upload, inspect the AAB signature, application ID, version, mapping file, native symbols if present, and merged release manifest. Retain the AAB, `mapping.txt`, dependency report, commit SHA, version inputs, and rollout configuration together.

## Security And Platform Checks

- Release cleartext traffic is denied. Debug permits only emulator host `10.0.2.2`; never ship the debug manifest/resource overlay.
- Only `MainActivity` is exported, for launcher and verified `https://plainstride.ai/account-link` links. Services, receivers, and providers must remain non-exported unless a documented platform contract requires otherwise.
- Publish and verify `/.well-known/assetlinks.json` for `com.plainstride.outbound` using the Play signing certificate, not the upload certificate.
- Cloud backup and device transfer are disabled for databases, preferences, files, root storage, and external app storage because these contain account sessions, precise activity tracks, health-derived records, and cached coaching/media data.
- Review the release merged manifest after every dependency update. Confirm permissions match actual UX education and Play declarations.

## Play Data Safety Inputs

Use these as form inputs, then validate against the actual production backend and enabled SDKs before submission:

| Data | Purpose | Handling |
| --- | --- | --- |
| Account identity and profile | Account management, personalization | Collected; encrypted in transit; deletion available |
| Precise location and activity route | Record activities, route guidance, optional live sharing | Collected only during user-started activity; encrypted in transit; not sold |
| Fitness/activity, optional health and heart rate | Activity history, progress, Health Connect import/export | User-controlled; health permissions are granular; excluded from product analytics |
| Photos selected/captured for an activity | Activity record | User initiated; private until explicit sharing |
| Contacts entered as trusted contacts | Optional safety sharing | User entered; not read from the system address book by default |
| App interactions and coarse diagnostics | Product analytics, reliability | No exact location, health facts, cue transcript, search text, or assistant prompt in analytics |
| Voice input | On-device/platform speech recognition for explicit assistant action | Ephemeral; disclosure must match the selected speech provider |

Data is not sold. Social publishing, live sharing, Health Connect, microphone, notifications, photos/camera, and location are optional and contextual. Account deletion must remove server data; local sign-out clears credentials. Reconcile this table with Play SDK disclosures and the public privacy policy on every release.

## Store Listing And Assets

- Localized listing inputs live under `android/play/listings/`; generation dimensions and source requirements live in `android/play/store-assets.json`.
- Required owner-reviewed output: 512×512 icon, 1024×500 feature graphic, phone screenshots, and—when Wear ships—separate watch screenshots.
- Capture screenshots from release-like builds with synthetic accounts. No real names, routes, contacts, health facts, access tokens, or notification content.
- A native speaker must review Spanish and Simplified Chinese listing copy and screenshots before upload.
- Complete the content rating, target audience, ads declaration, Health apps declaration, foreground-service declarations, account deletion URL, privacy policy URL, and Data safety form in Play Console.

### October 2026 Preparation

- Play package: `com.plainstride.outbound`; signed version `1.0` (3) was built, signature-verified, uploaded, confirmed, and submitted on the existing Alpha closed-testing track on October 18. Play shows **Changes in review**; automated quick checks were still running when submission was verified. This is closed testing, not a production release. The next upload must use a higher version code.
- The English listing is submitted with the Alpha release. Its icon, feature graphic, and four 1440×2560 phone screenshots are saved. Assets live under ignored `artifacts/play-store/en-US/`; raw Android captures are in `artifacts/play-store/raw/`.
- Screenshots show workout setup, Progress Now, Insights, and Trends. The demo emulator contains 60 synthetic local-only runs; fixture insertion added no sync outbox entries. Captures preserve the app image and aspect ratio inside a 9:16 promotional canvas. No real account identity, contacts, routes, or health history appears in the assets.
- The feature graphic is labeled as AI-generated, confirmed by the source manifest in `artifacts/app-store-creative/upload-en-US/asset-manifest.json`. Direct app captures are not labeled as AI artwork.
- Advertising ID is declared for Analytics because Firebase's merged release manifest includes `com.google.android.gms.permission.AD_ID`. This does not mean the app displays ads.
- Foreground-service declarations are saved for GPS workout recording (Other background location updates) and coaching media playback. The source and capture confirm user-started workout recording; the pre-set location-sharing category describes sharing with other people rather than recording a private workout. Google permits unlisted use cases in its declaration guidance: `https://support.google.com/googleplay/android-developer/answer/13392821`.
- A 70-second synthetic recording demonstration is retained at ignored `artifacts/play-store/foreground-recording-demo.mp4` and uploaded to Drive as file `1cstpdniJp1KIK8zSMRYGJSON9oEZpcrP`. The original copy remains private. An owner-approved reviewer copy is viewable at `https://drive.google.com/file/d/1eCCeD4ibf1gMoEZoSPrm32zZmNjVG9zu/view` with anyone-with-link Viewer access. This initial recording does not establish background survival or audible media playback.
- Play's privacy policy URL is saved as `https://run.plainstride.com/privacy`; the live Android/Health Connect policy was verified. The account deletion URL is `https://run.plainstride.com/support`, which provides in-app deletion instructions and an account/privacy contact. Avoid the older apex-domain iPhone policy.
- Data safety is saved with collection disclosed for identity/profile, approximate and precise location, purchases, messages, photos, voice recordings, health/fitness, trusted contacts, interactions, user content, and device identifiers. Search processing is declared ephemeral. Collection purposes and optionality were reconciled against the app, Firebase Analytics, and RevenueCat disclosures; processor and user-initiated sharing exemptions apply. No data sale or third-party advertising is declared.
- A second 87-second capture is retained at ignored `artifacts/play-store/foreground-coaching-demo.mp4`. It shows Voice Guide enabled, workout start, then Android background notifications for Recording activity and Plainstride coach (Coaching is active). The silent capture proves visible foreground-service state, not audible output. It is uploaded with anyone-with-link Viewer access at `https://drive.google.com/file/d/1WU_PUEx2JgobFm-ICXGUCO4Ix5X4hVFE/view` and attached to both foreground-service declarations.
- Dedicated reviewer credentials are saved in Play Console. Instructions explicitly use Continue with Google and explain that the password belongs to the Google account; Plainstride does not manage passwords. Never commit credentials.
- Final review corrected the health declaration: Activity and fitness plus optional Period tracking, with source-verified explanations for activity recognition, exercise/route import and export, distance, calories, and heart rate. Play then reported no blocking release errors and App content showed no declarations needing attention.
- One non-blocking Play warning remains: native debug symbols are not uploaded for dependency-provided native libraries. ReTrace mapping is attached. Do not interpret this warning as a runtime defect or claim native crash symbolication is available.
- All 13 pending changes were submitted together. Managed publishing is off, so approved changes can become available to the configured Alpha testers. Submission evidence is retained at ignored `artifacts/play-store/submitted-for-review.jpg`.
- Release shrinking suppresses only Ably's compile-time `lombok.Generated` annotation and SLF4J's optional `StaticLoggerBinder`; SLF4J retains its existing no-binding fallback. Do not suppress general missing-class warnings.
- Verification: signed `:app:bundleRelease` (including release configuration checks, vital lint, and R8), Play edit validation/commit, listing character limits, and diff whitespace checks succeeded. No tests were run. Full device runtime behavior and audible playback remain unverified; a successful build and draft upload do not clear those release gates.
- Local release evidence lives under ignored `artifacts/play-store/release-1.0-3/` (AAB, mapping, dependency report, and Play confirmation). Store assets and screenshots are kept out of source commits.
- Screenshot capture used the current debug build with the production API and synthetic emulator location. `:app:assembleDebug` succeeded; recording start, synthetic movement, pause, finish, and unsaved discard were exercised manually. This is focused capture verification, not the full release verification gate.

### October 20 Production Submission

- Bruce authorized public publishing and explicitly selected the United States and Canada.
- Alpha was already serving; the existing signed `1.0` (3) bundle was selected from Play's library for the first production release. No new binary was uploaded.
- Production country selection was initially empty. US and Canada are now configured, and the release passed blocking validation. The existing optional native-symbol warning remains.
- Production `1.0` (Start full rollout) and the two-country availability change were submitted together. Play shows **Changes in review**, with automated quick checks pending. Managed publishing is off, so approval will publish automatically; public availability is not yet confirmed.
- The pending country review was restarted to include the production binary rollout. Do not mistake the earlier country-only submission for a submitted binary.
- Evidence: ignored `artifacts/play-store/production-submitted-us-canada.jpg`. Continue treating Android as unreleased until Bruce explicitly confirms release, per `AGENTS.md`.

### October 31 Update Submission

- Bruce requested a new Android release. Build `1.0.1` (4) uses committed source `7ad610ba` in an isolated repository worktree; unrelated local edits are excluded.
- Production already reports `1.0` (3) as completed. Update `1.0.1` (4) was submitted through Play Console with a 10% staged rollout across the existing US/Canada availability. Play shows **Changes in review**, with automated quick checks still running. Managed publishing is off; approval can start the staged rollout automatically. Availability of this update is not yet confirmed.
- The existing protected `~/.config/plainstride/play-publisher.json` service account obtains the Android Publisher scope and can upload bundles/mappings and update tracks, but `edits.validate` returned HTTP 403 (`PERMISSION_DENIED`). Its uncommitted edit was discarded; publishing continued through the existing owner Play Console session. The active personal `gcloud` account cannot request the Publisher scope. Do not treat successful upload/track update as evidence of permission to validate or commit.
- Signed `:app:bundleRelease`, fail-closed release configuration checks, vital lint, R8, and bundle signature verification passed. Play Console showed no blocking errors and the existing optional native-debug-symbol warning; ReTrace mapping is attached. Supported device counts were unchanged.
- Release evidence is retained under ignored `artifacts/play-store/release-1.0.1-4/`: AAB, mapping, merged manifest, version inputs, source SHA, dependency report, endpoint checks, and `submitted-for-review.png`. The discarded API edit responses are upload evidence only, not submission evidence.
- Production `/health`, privacy, and support endpoints returned HTTP 200. `https://plainstride.ai/.well-known/assetlinks.json` returned HTTP 403, so app-link association remains unverified. Authenticated live-coach catalog, account deletion, device runtime, audible coaching, recording endurance, and accessibility were not exercised for this update. No tests were run.

### November 1 Open Testing Update Prepared

- Bruce requested a new build on the public test track. Signed `1.0.2` (5) was built from committed main `028a9b82` in an isolated worktree, excluding unrelated local edits, and uploaded to Open testing.
- Open testing was paused. The new release at 100% and track resumption are saved in Publishing overview with the existing two-country configuration. They are **not submitted**: Play requires restarting the production review pending since October 31. Automatic approval review blocked that restart pending explicit owner approval because it cancels/restarts the existing review and adds wait time.
- Signed bundle build, release configuration checks, vital lint, R8, and signature verification passed. Play showed no blocking errors; the existing native-symbol warning remains, and ReTrace mapping is attached. Device support counts are unchanged. Production `/health` returned HTTP 200. No tests or device runtime checks were run.
- Evidence is retained under ignored `artifacts/play-store/release-1.0.2-5/`: AAB, mapping, merged manifest, dependency report, source SHA, and `restart-review-required.png`. To finish, approve restarting the existing review, then submit the two saved Open testing changes through Publishing overview; managed publishing is off.

### November 3 Production Update Submission

- Bruce requested public releases of Android and iOS. Android `1.0.3` (6) was built from committed source `81e3cefd` in an isolated repository worktree, excluding unrelated local edits.
- The signed bundle passed release configuration checks, vital lint, R8, and signature verification. Play accepted the bundle with ReTrace mapping attached, unchanged supported-device counts, and only the existing optional native-debug-symbol warning.
- Production `1.0.3` was submitted at a 10% staged rollout across the existing two-country availability. Publishing overview confirms **Changes in review**; quick checks were still running. Managed publishing is off, so approval can start the rollout automatically. Bruce subsequently confirmed he manually changed the rollout to 100%; future releases follow the Production Rollout Policy above. This update is not yet confirmed publicly available.
- Production health and both platforms’ privacy/support endpoints returned HTTP 200. The Android association endpoint at `https://plainstride.ai/.well-known/assetlinks.json` returned HTTP 404; app-link handling remains unverified. No tests or device runtime acceptance checks were performed.
- Evidence is retained under ignored `artifacts/play-store/release-1.0.3-6/`: signed AAB, mapping, SHA-256, source SHA, product changes, and submission state. Existing Android unreleased-policy instructions remain in force until Bruce explicitly confirms release.

### November 6 Open Testing Submission

- Bruce requested a new public test release. Signed `1.0.4` (7) was built from committed main `24829e74` in an isolated worktree, excluding unrelated local files.
- Open testing was active in the existing two countries. Version 7 was uploaded with ReTrace mapping and submitted at 100%; Publishing overview confirms **Changes in review**, with quick checks running. Managed publishing is off, so approval publishes automatically. Availability is not yet confirmed.
- Signed bundle build, release configuration checks, vital lint, R8, and signature verification passed. Device support counts are unchanged; only the existing optional native-debug-symbol warning remains. No tests or device runtime checks were run.
- Changes include group invitations/member controls, recurring group events, coaching voice selection, and countdown playback. AAB, mapping, and source SHA are retained under ignored `artifacts/play-store/release-1.0.4-7/`.

## Dependencies And Notices

- Generate the release dependency graph with `./gradlew :app:dependencies --configuration releaseRuntimeClasspath` and archive it with the release.
- Direct dependencies are AndroidX/Jetpack, Kotlin/coroutines/serialization, Dagger/Hilt, Retrofit/OkHttp, Google Identity/Location, and Health Connect. Review their upstream license files and Play SDK disclosures before launch.
- Do not add an SDK with advertising, fingerprinting, or data-broker behavior without updating privacy review, consent UX, Data safety, and this document.
- Product analytics uses `FirebaseAnalyticsSink`, enables collection after sign-in, and uses the product analytics allowlist. Reconcile Firebase's SDK data and device-identifier disclosures with Data safety; adding another analytics/crash SDK requires updated privacy review and disclosures.

## Baseline Profile And Performance Gate

The `:benchmark` module contains cold-start Macrobenchmark and Baseline Profile generation journeys. These are device-only release tools and are not part of ordinary builds. Run them only when explicitly authorized, on a physical API 33+ device, then commit the generated profile in a focused change after comparing startup and frame metrics.

Release evidence should include cold startup, Today/recording navigation frame timing, 30-minute recording battery use, foreground-service survival with the screen locked, network-offline behavior, and accessibility checks at large font/display sizes.

## Monitoring, Kill Switches, And Rollback

Monitor authentication success, API error/latency, local-save and sync outcomes, foreground recording survival, ANR/crash-free users, Health Connect failures, live-share failures, and privacy-safe live-coach provider results. Alerts must not contain coordinates, health facts, prompts, transcripts, tokens, or user-entered text.

For production releases:

1. Verify backend compatibility and health, signed live-coach catalog, account deletion, and link association.
2. Use the 100% production rollout policy above and monitor release health after publishing.
3. Keep server-side live coach mode at `fixed_only` or `disabled` until device audio metrics are healthy; dynamic generation has its own rollout percentage and emergency switch.
4. Disable failing optional services server-side first. The app must retain recording, local save, offline history, and fixed/local coaching fallback.
5. Halt rollout on authentication, data-loss, recording, privacy, crash, or ANR regression.
6. For client rollback, promote the last known-good source as a new build with a higher version code. Never attempt to upload an older version code.
7. Preserve compatible backend auth and activity APIs while both client versions are active. Document any forced sign-in or destructive local reset in release notes.

Owner sign-off is required for production publishing. The publishing script can
commit a Play track release when invoked with `--publish`; check the destination
and release configuration before running it.
