# Android Build And Verification

Open this when configuring the Android toolchain, building the phone or Wear OS apps, or checking an Android phase before commit.

## Toolchain

- JDK 17
- Android SDK Platform 36.1 for compilation; the phone app targets API 36
- Android SDK Platform 35 or newer for Wear OS
- Android SDK Build Tools 36.0.0
- The checked-in Gradle wrapper under `android/`

The fixed iOS/shared-server comparison point is stored in `android/ios-baseline.toml`. Do not update it during the Android phase plan; audit and advance it only after the post-Phase-9 parity catch-up is complete.

Set `ANDROID_HOME` or create an untracked `android/local.properties` with the local SDK path. Never commit a machine-specific SDK path.

## Unreleased Android Data Policy

Android remains unreleased until Bruce explicitly confirms release. Follow `AGENTS.md`: use only current models, with no app-version migration or historical-payload compatibility code. Room opens `plainstride-v<schema-version>.db`; a schema change creates clean local data and does not copy an older database. Only the current schema export is retained.

For an explicit full development reset (also clears login/preferences/media):

```sh
adb shell pm clear com.plainstride.outbound.debug
```

Backend data is not reset and can synchronize after sign-in. Supported Android OS API handling and current backend/iOS contracts still apply.

## Build-Only Verification

Run from `android/`:

```sh
./gradlew :app:assembleDebug :app:assembleRelease :wear:assembleDebug :wear:assembleRelease
./gradlew lint
```

The build must not require Firebase files, signing secrets, provider credentials, or a reachable backend. Release publishing configuration will be added only through secret-backed local or CI inputs.

For shared coach-wording or fallback-resource changes, a focused compile is sufficient:

```sh
./gradlew :feature:livecoach:compileDebugKotlin
```

`backend/scripts/verify-live-coach-cues.mjs` also checks current Android fallback keys and all three locales against the shared recorded catalog. It does not establish Android device audibility.

## Variants

Android 12+ uses `plainstride_splash_icon` with proportional padding to keep the
complete fox inside the system's circular splash mask. Keep this separate from
the launcher foreground, whose fixed insets serve a different canvas. For visual
verification, cold-launch on a device and capture the splash before the app loads.

- `debug`: uses the production API URL by default and permits explicit debug identity tooling.
- `release`: uses the production API URL, disables debug identity tooling, enables code shrinking, and contains no debug credentials or endpoints.

The debug package is registered in Firebase as `com.plainstride.outbound.debug` and uses its own Firebase application ID. Override that ID with `PLAINSTRIDE_FIREBASE_DEBUG_APPLICATION_ID` only when targeting a different Firebase project; the Google server client ID remains shared with release. Gradle also emits the Firebase application ID, API key, project ID, and messaging sender ID as Android string resources so Firebase's startup provider can initialize Analytics and Messaging before `Application.onCreate`. Override the default sender ID with `PLAINSTRIDE_FIREBASE_MESSAGING_SENDER_ID` when targeting another project.

Debug builds use the RevenueCat Test Store key by default; override it with `PLAINSTRIDE_REVENUECAT_DEBUG_PUBLIC_SDK_KEY`. Set the production Google RevenueCat SDK key as `PLAINSTRIDE_REVENUECAT_PUBLIC_SDK_KEY`; Play release verification rejects an absent key or a `test_` key. See `docs/subscriptions.md` before enabling it in a store build.

Application startup enforces that debug identity support cannot be enabled in a release build.

To develop against a backend running on the Android emulator host, override the debug API URL:

```sh
./gradlew :app:assembleDebug -PPLAINSTRIDE_DEBUG_API_BASE_URL=http://10.0.2.2:8787
```

Network diagnostics log request methods and paths, response status/request IDs, timing, and exception types under `PlainstrideNetwork`. Authentication stages use `PlainstrideAuth`, `PlainstrideGoogleAuth`, and `PlainstrideAuthRepo`. Tokens, transfer codes, account IDs, email addresses, request bodies, headers, and query values are never logged.

## Signed Release Install

Connect and authorize an Android phone, then run from the repository root:

```sh
./scripts/build-install-android-release.sh
```

The helper loads the existing upload-key passwords from macOS Keychain, uses the
keystore at `~/.config/plainstride/android-upload.jks`, and reads production
Gradle properties from `~/.gradle/gradle.properties`. It validates the Play
release configuration, builds the minified signed phone APK, verifies its
certificate, and installs it with `adb install -r`. Set `ANDROID_SERIAL` first
when more than one device is connected. Override `PLAINSTRIDE_VERSION_CODE` and
`PLAINSTRIDE_VERSION_NAME` when preparing an upload; local installs default to
version code `1` and version name `1.0`.

## Tests

Do not run the test suite unless explicitly requested. Each Android phase still needs its documented build, lint, static, and manual verification gate.
