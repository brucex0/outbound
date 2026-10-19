# Android Play Release

Open this for Play Console preparation, signed bundles, release policy, privacy review, performance profiles, or production rollback. This document does not authorize publishing.

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

- Play package: `com.plainstride.outbound`; signed version `1.0` (3) was built, signature-verified, uploaded, and saved on the existing Alpha closed-testing track as a draft on October 18. The next upload must use a higher version code.
- The English listing is **Ready to send for review** in Play Console. Its icon, feature graphic, and four 1440×2560 phone screenshots are saved. Assets live under ignored `artifacts/play-store/en-US/`; raw Android captures are in `artifacts/play-store/raw/`.
- Screenshots show workout setup, Progress Now, Insights, and Trends. The demo emulator contains 60 synthetic local-only runs; fixture insertion added no sync outbox entries. Captures preserve the app image and aspect ratio inside a 9:16 promotional canvas. No real account identity, contacts, routes, or health history appears in the assets.
- The feature graphic is labeled as AI-generated, confirmed by the source manifest in `artifacts/app-store-creative/upload-en-US/asset-manifest.json`. Direct app captures are not labeled as AI artwork.
- Advertising ID is declared for Analytics because Firebase's merged release manifest includes `com.google.android.gms.permission.AD_ID`. This does not mean the app displays ads.
- Foreground location (activity recording and explicit live sharing) and media playback (coaching audio) require reviewer-accessible demonstration video links before their Play declarations can be saved.
- A 70-second synthetic recording demonstration is retained at ignored `artifacts/play-store/foreground-recording-demo.mp4` and uploaded to Drive as file `1cstpdniJp1KIK8zSMRYGJSON9oEZpcrP`. It remains private until the owner approves link sharing. It does not establish background survival or audible media playback; verify those separately before using it to substantiate those claims.
- Play's privacy policy URL now points at `https://plainstride.ai/privacy`, rather than the homepage. The live policy must include Android/Health Connect disclosures; on October 18 the live page still showed the older iPhone policy despite newer source in `backend/src/routes/marketing.ts`.
- Reviewer access remains incomplete: the saved instructions say any Google test account works but provide no dedicated credentials. Play explicitly says reviewers cannot create or use their own accounts; supply a dedicated review account with access to paid features before submission. Never commit its credentials.
- Release shrinking suppresses only Ably's compile-time `lombok.Generated` annotation and SLF4J's optional `StaticLoggerBinder`; SLF4J retains its existing no-binding fallback. Do not suppress general missing-class warnings.
- Verification: signed `:app:bundleRelease` (including release configuration checks, vital lint, and R8), Play edit validation/commit, listing character limits, and diff whitespace checks succeeded. No tests were run. Device runtime behavior, recording survival, audio playback, and the full Data safety reconciliation remain unverified; a successful build and draft upload do not clear those release gates.
- Local release evidence lives under ignored `artifacts/play-store/release-1.0-3/` (AAB, mapping, dependency report, and Play confirmation). Store assets and screenshots are kept out of source commits.
- Screenshot capture used the current debug build with the production API and synthetic emulator location. `:app:assembleDebug` succeeded; recording start, synthetic movement, pause, finish, and unsaved discard were exercised manually. This is focused capture verification, not the full release verification gate.

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

Before widening production rollout:

1. Verify backend compatibility and health, signed live-coach catalog, account deletion, and link association.
2. Start with the smallest Play staged rollout cohort and observe a full daily usage cycle.
3. Keep server-side live coach mode at `fixed_only` or `disabled` until device audio metrics are healthy; dynamic generation has its own rollout percentage and emergency switch.
4. Disable failing optional services server-side first. The app must retain recording, local save, offline history, and fixed/local coaching fallback.
5. Halt rollout on authentication, data-loss, recording, privacy, crash, or ANR regression.
6. For client rollback, promote the last known-good source as a new build with a higher version code. Never attempt to upload an older version code.
7. Preserve compatible backend auth and activity APIs while both client versions are active. Document any forced sign-in or destructive local reset in release notes.

Owner sign-off is required for production publishing. The publishing script can
commit a Play track release when invoked with `--publish`; check the destination
and release configuration before running it.
