# Build, Test, Signing, And Device Notes

Open this when validating changes, installing on device, editing signing settings, or debugging simulator/device execution.

## Signing And Entitlements

- Bundle ID: `plainstride.outbound`.
- Development team in the project: Plainstride Labs Inc. (`WT54K7D7VH`).
- Current iOS deployment target in Xcode: `18.0`.
- Version 1 targets iPhone only (`TARGETED_DEVICE_FAMILY = 1`).
- Debug device builds use `ios/Outbound/SupportFiles/OutboundDebug.entitlements`, and Release builds use `ios/Outbound/SupportFiles/Outbound.entitlements`.
- Both configurations include Sign in with Apple, HealthKit, and WeatherKit for the paid Plainstride Labs team.
- Use a paid Apple Developer team before validating Apple provider sign-in on device or shipping.
- Do not add `aps-environment`, HealthKit clinical-record access, or HealthKit background delivery unless the matching capability and implementation are required.
- Device installs still require an Apple Development identity and iOS Development provisioning profiles for both `plainstride.outbound` and `plainstride.outbound.liveactivity`.
- To refresh signing in Xcode: open `ios/Outbound/Outbound.xcodeproj`, go to Xcode Settings > Accounts, select the Apple ID for Plainstride Labs Inc. (`WT54K7D7VH`), use Manage Certificates to create an Apple Development certificate if needed, then select both the `Outbound` app target and `OutboundLiveActivityExtension` target and keep Automatically manage signing enabled with team `WT54K7D7VH`.
- If Xcode offers to register `Bruce main` or create/download provisioning profiles during the next build, allow it.

If a device build fails because `codesign` cannot access the signing key in the login keychain, run:

```sh
./scripts/fix-codesign-keychain.sh
```

Enter the Mac login password when prompted. The helper unlocks `~/Library/Keychains/login.keychain-db` and grants Apple tooling and `codesign` access to its keys. It does not store or print the password.

## Device IDs

- User device name: `Bruce main`.
- CoreDevice ID: `591E461F-4950-5FBD-A797-4777F1E83532`.
- The device UDID may still appear inside `devicectl` JSON and local hostnames, but the build helper no longer depends on Xcode listing the phone as a direct build destination.
- If launch fails with "profile has not been explicitly trusted by the user", trust the personal development profile on the phone: Settings -> General -> VPN & Device Management -> Developer App -> Trust.

## Build-Only Checks

Use build-only checks for normal validation. Do not run tests unless the user asks.

```sh
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'generic/platform=iOS Simulator' build
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Test Commands

Run tests only when the user asks.

```sh
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'id=90D55095-943A-416B-B91F-01EA17807713' -parallel-testing-enabled NO test
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'id=90D55095-943A-416B-B91F-01EA17807713' -parallel-testing-enabled NO -only-testing:OutboundUITests test
swift test
```

Run the complete deterministic app UI regression suite. It selects the first available iPhone simulator unless an explicit Xcode destination is supplied:

```sh
./scripts/run-app-tests.sh
./scripts/run-app-tests.sh 'id=SIMULATOR_UUID'
```

This suite covers the primary shell and navigation, installed iOS guide voice previews, seeded Social connections, requests, groups, notifications, group-run RSVP, Cheers, comments and activity sharing, activity history, Settings, recording and post-run lifecycle, a deterministic live 10K run with route and health metrics, and launch performance. It uses local UI-test authentication, deterministic in-memory fixtures, and skips onboarding; use `run-local-e2e.sh` separately for Firebase and server persona coverage. Standalone DEBUG harness tests are intentionally outside this production-flow suite.

### Seeded Live 10K

The focused automated test is `OutboundUITests.testSeededLive10KRunMetricsAndLifecycle`. It runs on a simulator with local UI-test authentication, not a Firebase test account:

```sh
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination 'id=SIMULATOR_UUID' \
  -derivedDataPath /tmp/outbound-app-test-derived \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  -only-testing:OutboundUITests/OutboundUITests/testSeededLive10KRunMetricsAndLifecycle \
  test
```

The fixture opens a 10 km goal in progress at 7.82 km, 45:53 elapsed time, 5:41/km current pace, 61 m elevation gain, 152 bpm heart rate, and a deterministic San Francisco street loop. The completed summary reports a 5:52/km average pace. The test verifies pause, resume, finish, summary metrics, and discard. The seed code and launch trigger are compiled only in Debug; Release builds do not contain them.

To exercise the same lifecycle manually on `Bruce main` while using the Firebase test account already signed into the app:

1. End or discard any real session currently in progress. Install a fresh Debug build without launching it:

   ```sh
   ./scripts/build-install-bruce-main.sh
   ```

2. Unlock the phone, then launch the installed app with the seed flag:

   ```sh
   xcrun devicectl device process launch \
     --terminate-existing \
     --device 591E461F-4950-5FBD-A797-4777F1E83532 \
     plainstride.outbound \
     -- \
     -OutboundUITestLive10K \
     -measurement_unit_system_v1 metric
   ```

   The `--` ends `devicectl` option parsing. Without it, `devicectl` can mistake the app's `-measurement_unit_system_v1` argument for its own `-t` timeout option.

3. If the app is signed out, sign in normally with the test account. On Today, tap **Quick start**. Opening the recording screen activates the seeded live run immediately; no countdown, GPS movement, HealthKit sample, or hour-long wait is required.
4. Confirm the map route and metrics, then use **Pause**, **Resume**, **Pause**, and **Finish**. On the summary, choose **Discard activity** unless the seeded run is intentionally meant to be saved and synchronized to the test account.

Launching the app normally afterward, including with `./scripts/build-install-bruce-main.sh --launch`, omits the seed flag. The flag does not replace or bypass Firebase authentication on a physical device.

Run the automated local server E2E test with one seeded persona. The runner starts and stops Firebase Auth, the local API, and embedded PostgreSQL; resets deterministic seed data; obtains a real emulator ID token; then verifies authenticated account, activity, and social API state:

```sh
./scripts/run-local-e2e.sh new
./scripts/run-local-e2e.sh active
./scripts/run-local-e2e.sh social
```

API and database ports can be overridden with `OUTBOUND_E2E_API_PORT` and `OUTBOUND_E2E_DATABASE_PORT`; Firebase Auth uses the repository's configured emulator port `9099`. The script refuses occupied ports and prints its temporary log directory on completion. This command tests the real local authentication and server boundary; simulator UI tests remain separate.

The simulator ID above is the current available `iPhone 17` simulator used for stable UI test runs. If that simulator disappears, rerun `xcodebuild` once to inspect the available destination list and refresh this doc.

## Device Build And Install

Preferred shortcut:

```sh
./scripts/build-install-bruce-main.sh
```

The helper now prints timestamped phase logs and streams `xcodebuild` output, so if it appears slow you can see whether it is still in the build, device-check, install, or launch step.
For install builds, it reports missing local signing inputs and still runs `xcodebuild -allowProvisioningUpdates` so Xcode can refresh certificates and provisioning profiles from the signed-in account.

If Xcode itself shows stale package errors for dependencies that are no longer in the project, clear only Outbound's local DerivedData entries and reopen the project:

```sh
backup_dir=/tmp/outbound-xcode-derived-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup_dir"
for dir in ~/Library/Developer/Xcode/DerivedData/Outbound-*; do
  [ -e "$dir" ] || continue
  mv "$dir" "$backup_dir"/
done
```

This project previously hit an Xcode state where stale `Blueprint.xcscmblueprint` package metadata caused indexing and package resolution to hang.

Build without installing:

```sh
./scripts/build-install-bruce-main.sh --build-only
```

This mode disables code signing with `CODE_SIGNING_ALLOWED=NO`, so it is useful for compile validation even when Xcode is not signed into an Apple Developer account. The output app is not installable on a physical device.

Social is disabled by default for beta/App Review builds. To compile the optional Social tab locally:

```sh
./scripts/build-install-bruce-main.sh --build-only --with-social
```

Use `--without-social` to make the default explicit:

```sh
./scripts/build-install-bruce-main.sh --build-only --without-social
```

Build, install, and launch:

```sh
./scripts/build-install-bruce-main.sh --launch
```

Underlying commands:

```sh
xcodebuild -allowProvisioningUpdates \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme Outbound \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/outbound-device-derived \
  -showBuildTimingSummary \
  build

xcrun devicectl device install app \
  --device 591E461F-4950-5FBD-A797-4777F1E83532 \
  /tmp/outbound-device-derived/Build/Products/Debug-iphoneos/Outbound.app
```

Optional launch, only when the phone is unlocked:

```sh
xcrun devicectl device process launch \
  --device 591E461F-4950-5FBD-A797-4777F1E83532 \
  plainstride.outbound
```
