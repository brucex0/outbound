# Android Play Release

Open this for Play Console preparation, signed bundles, release policy, privacy review, performance profiles, or production rollback. This document does not authorize publishing.

## Version And Signing Policy

- `PLAINSTRIDE_VERSION_CODE` is a monotonically increasing positive integer assigned by CI for every Play upload.
- `PLAINSTRIDE_VERSION_NAME` is the user-facing semantic version. A rollback build still receives a new version code.
- Enroll in Play App Signing and protect the upload key separately. Never commit a keystore or password.
- Supply `PLAINSTRIDE_ANDROID_KEYSTORE_PATH`, `PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD`, `PLAINSTRIDE_ANDROID_KEY_ALIAS`, and `PLAINSTRIDE_ANDROID_KEY_PASSWORD` only through the CI secret store or local environment.
- Ordinary `assembleRelease` remains unsigned when secrets are absent so source verification is reproducible. Run `verifyPlayReleaseConfiguration` before any Play bundle.

```sh
./gradlew :app:verifyPlayReleaseConfiguration :app:bundleRelease
```

Before upload, inspect the AAB signature, application ID, version, mapping file, native symbols if present, and merged release manifest. Retain the AAB, `mapping.txt`, dependency report, commit SHA, version inputs, and rollout configuration together.

## Security And Platform Checks

- Release cleartext traffic is denied. Debug permits only emulator host `10.0.2.2`; never ship the debug manifest/resource overlay.
- Only `MainActivity` is exported, for launcher and verified `https://run.plainstride.com/account-link` links. Services, receivers, and providers must remain non-exported unless a documented platform contract requires otherwise.
- Publish and verify `/.well-known/assetlinks.json` for `run.plainstride.app` using the Play signing certificate, not the upload certificate.
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

## Dependencies And Notices

- Generate the release dependency graph with `./gradlew :app:dependencies --configuration releaseRuntimeClasspath` and archive it with the release.
- Direct dependencies are AndroidX/Jetpack, Kotlin/coroutines/serialization, Dagger/Hilt, Retrofit/OkHttp, Google Identity/Location, and Health Connect. Review their upstream license files and Play SDK disclosures before launch.
- Do not add an SDK with advertising, fingerprinting, or data-broker behavior without updating privacy review, consent UX, Data safety, and this document.
- Current product analytics uses a no-op sink. Enabling a production analytics/crash SDK requires a separate privacy-reviewed change and updated disclosures.

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

Owner sign-off is required for production publishing; this repository workflow only prepares and verifies artifacts.
