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

## Build-Only Verification

Run from `android/`:

```sh
./gradlew :app:assembleDebug :app:assembleRelease :wear:assembleDebug :wear:assembleRelease
./gradlew lint
```

The build must not require Firebase files, signing secrets, provider credentials, or a reachable backend. Release publishing configuration will be added only through secret-backed local or CI inputs.

## Variants

- `debug`: uses the emulator loopback API URL and permits explicit debug identity tooling.
- `release`: uses the production API URL, disables debug identity tooling, enables code shrinking, and contains no debug credentials or endpoints.

Application startup enforces that debug identity support cannot be enabled in a release build.

## Tests

Do not run the test suite unless explicitly requested. Each Android phase still needs its documented build, lint, static, and manual verification gate.
