# Build, Test, Signing, And Device Notes

Open this when validating changes, installing on device, editing signing settings, or debugging simulator/device execution.

## Signing And Entitlements

- Bundle ID: `plainstride.outbound`.
- Watch background modes: `WKBackgroundModes = [workout-processing]` and `UIBackgroundModes = [location]`. Keep location out of `WKBackgroundModes`; App Store validation rejects it there. Both declarations are needed for workout processing and standalone background route recording.
- Watch app bundle ID: `plainstride.outbound.watchkitapp`; its companion bundle ID is `plainstride.outbound`.
- Development team in the project: Plainstride Labs Inc. (`WT54K7D7VH`).
- Current iOS deployment target in Xcode: `18.0`.
- Version 1 targets iPhone only (`TARGETED_DEVICE_FAMILY = 1`) and supports portrait orientation only. Revisit iPad orientation and multitasking behavior separately if iPad support is added.
- Debug device builds use `ios/Outbound/SupportFiles/OutboundDebug.entitlements`, and Release builds use `ios/Outbound/SupportFiles/Outbound.entitlements`.
- Both configurations include Sign in with Apple, HealthKit, and WeatherKit for the paid Plainstride Labs team.
- The app and `OutboundLiveActivityExtension` share the `group.ai.plainstride.shared` App Group so the Home Screen widget can read the app-published workout suggestion. Keep this capability enabled in both app entitlements and the extension provisioning profile.
- Use a paid Apple Developer team before validating Apple provider sign-in on device or shipping.
- Do not add `aps-environment`, HealthKit clinical-record access, or HealthKit background delivery unless the matching capability and implementation are required.
- Device installs still require an Apple Development identity and development provisioning profiles for `plainstride.outbound`, `plainstride.outbound.liveactivity`, and `plainstride.outbound.watchkitapp`.
- To refresh signing in Xcode: open `ios/Outbound/Outbound.xcodeproj`, go to Xcode Settings > Accounts, select the Apple ID for Plainstride Labs Inc. (`WT54K7D7VH`), use Manage Certificates to create an Apple Development certificate if needed, then select `Outbound`, `OutboundLiveActivityExtension`, and `Plainstride Watch` and keep Automatically manage signing enabled with team `WT54K7D7VH`.
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

## Read Device Coaching Logs

- Prefer the connected phone's Console stream filtered to process `Outbound`. Read recent history with `log collect --device-udid DEVICE_UDID --last 30m`; Apple's attached-device collector requires administrator access. Never restart an active recording just to attach a console.
- When Console is stalled and administrator access is unavailable, `pymobiledevice3` can read the existing Apple tunnel. Install it in a temporary virtual environment, then use the selected phone's actual UDID:

  ```sh
  python -m pymobiledevice3 syslog live --native --udid DEVICE_UDID \
    --process-name Outbound --insensitive-regex 'coach|cadence|guide|speech|audio'
  ```

- `--native` can temporarily displace Xcode/CoreDevice's tunnel connection; it does not restart the app. Stop this reader before opening another native reader. USB devices can omit `--native`.
- Historical `syslog collect` archives may contain unrelated private device logs. Keep them local, filter to the app's coaching/audio diagnostics, and remove the broad temporary archive after extracting the necessary evidence. Never paste tokens, request bodies, location, or user content into diagnostics or commits.
- Beat diagnostics are in subsystem `com.plainstride`, category `CadencePacer`; session/prewarm errors use `plainstride.outbound`, category `ActivityLifecycle`. See `docs/live-coach-operations.md` for the confirmed prewarm incident and the distinction between playback requests and listening verification.

## Build-Only Checks

Use build-only checks for normal validation. Do not run tests unless the user asks.

```sh
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'generic/platform=iOS Simulator' build
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme 'Plainstride Watch' -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

### Recovering Build Environment Failures

- If backend build reports `sh: tsc: command not found`, the backend dependencies are missing. From the repository root, install the locked dependencies and retry the compile:

  ```sh
  cd backend
  npm ci
  npm run build
  ```

  This is a local dependency-install issue; do not change `package.json` or the lockfile to work around it.
- If Xcode fails package resolution because it cannot write `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading/*.dia`, the failure is the host sandbox denying SwiftPM's manifest diagnostic cache writes. Moving DerivedData, cloned packages, and package cache to `/tmp` alone does not redirect this cache. In the restricted shell, forcing `HOME`/`CFFIXED_USER_HOME` to `/tmp` changed the error to `sandbox-exec: sandbox_apply: Operation not permitted`.
- The working recovery was to run the normal `xcodebuild` with host cache/build-service access, while keeping generated build/package data in `/tmp`:

  ```sh
  xcodebuild -quiet \
    -project ios/Outbound/Outbound.xcodeproj \
    -scheme Outbound \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/outbound-groups-derived \
    -clonedSourcePackagesDirPath /tmp/outbound-groups-source-packages \
    -packageCachePath /tmp/outbound-package-cache \
    CODE_SIGNING_ALLOWED=NO build
  ```

  If the execution sandbox still denies host cache writes, request the needed elevated execution access instead of repeating cache-path overrides. CoreSimulator connection warnings can appear in this environment; the generic simulator build still completed successfully after package resolution.

The Watch scheme requires the matching watchOS platform component in Xcode. If the host has SDK headers but reports that watchOS is not installed, install the watchOS device platform in Xcode Settings > Components before relying on the scheme build. A compiler-only fallback can type-check the Watch and shared Swift sources against the installed SDK, but it does not validate embedding or signing.

## Xcode 27.1 And iPhone Duo

- Xcode 27.1 uses **Device Hub** at `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`; an older running Simulator interface can retain stale device/runtime lists after an update.
- Confirm setup with `xcodebuild -version`, `xcodebuild -checkFirstLaunchStatus`, `xcrun simctl list runtimes`, and `xcrun simctl list devicetypes` before selecting a Duo destination. First launch may require accepting the Xcode/SDK agreement and installing platform components.
- Use a fresh Duo simulator with local synthetic fixtures for layout checks. Device Hub exposes Closed, Partially Open, Open, and rotation controls. Check state retention across transitions, vertical bars, asymmetric safe areas, sheets, keyboard avoidance, and scrolling; a build alone does not establish readiness.
- `xcrun simctl io SIMULATOR_UUID enumerate` identifies display names. Capture the active outer display with `screenshot --display=primary OUTPUT.png` and inner display with `screenshot --display=primary-1 OUTPUT.png`. An inactive display can capture as black; inspect pixels and actual dimensions before treating a capture as evidence.
- Expected App Store dimensions are outer `1398 × 2034` and inner `2007 × 2853`, or reversed for landscape. Recheck [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) before preparing assets. Submitting Duo screenshots triggers an optimized-for-Duo badge, so Debug fixture captures and build success are not sufficient release evidence.
- Manual English checks on 2026-10-17 reached activity setup, Cheer Me On, plan text entry, Progress, group activity detail, and synthetic recording/pause/finish/save/stretch with fold transitions. This was partial coverage: full onboarding, software keyboard avoidance, reliable scroll reachability, all poses/orientations, and two-participant live sharing remain unverified. No Duo readiness claim or store screenshot submission was made.

## Apple Watch Paired-Device Validation

- In Xcode, select a paired iPhone + Apple Watch destination and run the `Outbound` scheme; confirm `Plainstride Watch.app` is embedded and installs on the watch.
- Grant Health access on Apple Watch, then start once from iPhone and once from Watch. In both directions confirm one session, matching elapsed time, live BPM/effort, and pause/resume/finish from either device.
- During an active workout, move the devices out of range or disable the connection. Confirm both surfaces say recording continues, route recording remains active on iPhone, and controls reconcile after reconnection.
- Terminate and relaunch each app during an active workout. Confirm Watch recovers the HealthKit session and iPhone returns to the same Plainstride activity rather than creating a second record.
- Finish while disconnected, reconnect, and confirm the delayed Apple Health workout UUID attaches to the existing activity. A later Apple Health import scan must not offer that workout again.
- Deny Watch Health authorization or test without a paired/available Watch. After the six-second preparation window, confirm the iPhone begins a normal phone-only workout and performs its usual HealthKit write-back.

After pulling the destructive pre-release Social Groups schema replacement, rebuild local backend data and generated Prisma types before launching the app:

```sh
cd backend
npm run db:rebuild
```

For a non-destructive compile-only backend check, use `npm run db:generate && npm run build`.

## Test Commands

Run tests only when the user asks.

```sh
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'id=90D55095-943A-416B-B91F-01EA17807713' -parallel-testing-enabled NO test
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'id=90D55095-943A-416B-B91F-01EA17807713' -parallel-testing-enabled NO -only-testing:OutboundUITests test
swift test
```

### Focused Speed-Warning Regression Tests

When requested, run only the detector and recorder/guide pipeline tests on a dedicated simulator:

```sh
xcodebuild -quiet -jobs 2 \
  -project ios/Outbound/Outbound.xcodeproj -scheme Outbound \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  -only-testing:OutboundTests/SuddenSpeedChangeDetectorTests \
  -only-testing:OutboundTests/SpeedWarningPipelineTests \
  'EXCLUDED_SOURCE_FILE_NAMES=HealthKitStoreTests.swift OutboundTests.swift LocalActivityStorePhotoTests.swift' \
  CODE_SIGNING_ALLOWED=NO test
```

The source exclusion avoids existing stale `HealthKitServing`/`MusicService` mocks and tests referring to the removed `LocalActivityStore`. Remove it once those unrelated tests are repaired; `-only-testing` filters execution but still compiles the unit-test target.

The tests advance sensor/session timestamps synchronously and capture audio requests. They cover detector gates, 4→19/6→24/7→24/24→7 km/h recorder ramps at 1×/10×, recent target coaching, busy/stale queues, unavailable/failed playback, and both directions through the actual generated WAV files. Across EN/ES/ZH and both voices, every iOS fallback must have a matching recording; countdown lookup and rejection of unrelated sentences remain intact. An older cached manifest must not hide bundled warnings. Positive checks use the approved app bundle directly and prepare every cue with AVAudioPlayer. A separate unreviewed fixture verifies approval rejection. These checks do not establish physical audibility or listening QA. The simulation creates and clears a recovery journal inside its dedicated simulator and never saves/syncs an activity.

Check backend cue/locale/display mappings and fallback-plan integrity without network or AI calls:

```sh
cd backend
npm run build
node scripts/verify-live-coach-cues.mjs
```


### Complete App UI Regression Suite

Run the complete deterministic app UI regression suite. It selects the first available iPhone simulator unless an explicit Xcode destination is supplied:

```sh
./scripts/run-app-tests.sh
./scripts/run-app-tests.sh 'id=SIMULATOR_UUID'
```

This suite covers the primary shell and navigation, installed iOS guide voice previews, seeded Social connections, requests, groups, notifications, group-run RSVP, Cheers, comments and activity sharing, activity history, Settings, recording and post-run lifecycle, a deterministic live 10K run with route and health metrics, and launch performance. It uses local UI-test authentication, deterministic in-memory fixtures, and skips onboarding; use `run-local-e2e.sh` separately for Firebase and server persona coverage. Standalone DEBUG harness tests are intentionally outside this production-flow suite.

### On-Demand UI Flows From Terminal

```sh
./scripts/run-ui-flow.sh --list
./scripts/run-ui-flow.sh appearance
./scripts/run-ui-flow.sh appearance-palette
# Explicit simulator or connected test iPhone (use its Xcode UDID):
./scripts/run-ui-flow.sh appearance 'platform=iOS Simulator,id=SIMULATOR_UUID'
./scripts/run-ui-flow.sh appearance 'platform=iOS,id=DEVICE_UDID'
```

- Each command runs only the named XCTest UI flow. The default creates and removes a dedicated iPhone simulator, preserving existing simulator apps and data.
- `appearance` verifies that the tip and all four toolbar controls are visible, tappable, and do not overlap, then taps the pill, verifies the chooser, and returns to the toolbar. `appearance-palette` checks the palette path while the tip is visible.
- Screenshots and XCTest assertions are retained in `Flow.xcresult`, with the build/test log in the fresh `/tmp/plainstride-ui-flow.*` directory printed by the runner. Open the result bundle in Xcode to inspect failures and screenshots. The command returns nonzero on failure.
- Connected phones require pairing, Developer Mode, an unlocked screen, and valid development signing. Use a dedicated test phone: flows relaunch the app with local test authentication and fixtures, and some scenarios change local app state. They do not test production sign-in.
- The runner controls the app through Apple's XCTest runner; no network command listener is added to the app. Device availability and signing are reported by `xcodebuild`.
- Add a focused test to `UIFlowTests.swift` with stable accessibility identifiers and meaningful visible-state assertions, then register its name in the script's `case` list. Keep fixture setup in launch arguments and retain screenshots at key transitions. Do not map a flow to the entire suite.
- Run one command at a time; runners share `/tmp/plainstride-ui-flow-derived` to reuse build products.

### Watch And Phone-Only Regression Flows

```sh
./scripts/run-watch-flow-tests.sh
# Or an existing iPhone simulator (never a personal device):
./scripts/run-watch-flow-tests.sh 'platform=iOS Simulator,id=SIMULATOR_UUID'
```

- Historical recorder-selector baseline on an unpaired iOS 26.5 iPhone 17 Pro simulator: six passed, zero failed or skipped (2026-10-16). The revised Watch app off fixture and Health-save policy have not been rerun; tests require an explicit user request.
- Runs only `WatchWorkoutFlowUITests`: unavailable Watch, preparation timeout, connected phone controls, remote controls/disconnect/reconnect/stale messages, Watch app off with phone Health write-back ownership, and Watch save failure.
- Each flow records a seeded eligible activity, pauses/resumes/finishes, saves through the real review screen, checks exactly one activity with the expected Health ownership/reference, and exits the celebration through Done without starting another recording. The explicit simulator fixture clears its recording recovery journal on launch so failed scenarios cannot contaminate the next case.
- The default creates and removes an isolated iPhone 17 Pro simulator. Results and screenshots remain in the printed `/tmp/plainstride-watch-flows.*` directory. Run one instance at a time because the build cache is shared.
- Uses a DEBUG simulator-only transport behind both seeded-data and explicit scenario flags. Messages pass through the real codec/coordinator; only Watch launch and outgoing transport are replaced. No fixture code is compiled into Release or physical-device builds.
- These checks establish phone lifecycle, message ordering, fallback, Health persistence ownership, and visible save completion under the fixture. They do not establish physical Watch installation, real HealthKit mirroring, sensor/GPS accuracy, Health sync, haptics, or battery life. Keep paired-device validation above as a separate release gate.

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

Launching the app normally afterward, including with `./scripts/build-install-bruce-main.sh --launch`, omits the seed flag. The flag does not replace or bypass first-party authentication on a physical device.

### Interactive Redmond Run Simulation

Use the DEBUG-only simulator to manually verify evolving map rendering, Route Guidance, and the real live voice-guide pipeline without moving the phone:

```sh
./scripts/build-install-bruce-main.sh --launch --simulated-run
```

Add `--simulator` to run it in an iPhone Simulator. The launch flag preselects the Redmond Harvest route on Today; it does not bypass authentication or start recording automatically.

1. Confirm Voice Guide is enabled, then tap Start and let the normal spoken countdown finish.
2. In the Run Simulation overlay, change the simulated running speed with minus/plus.
3. Use Play to advance continuously. Select 1×, 10×, or 60× to control simulated-time acceleration, or use `+1m` and `+5m` for deterministic jumps.
4. Watch the orange recorded trail, current-position marker, route progress, pace, distance, and guide message update from the same recorder snapshots used by a real outdoor run.
5. Pause/Resume with the normal session controls. When finished, choose Discard activity so the synthetic workout is not saved or synchronized.

Without the launch flag, the same simulator is available in a Debug build from the activity setup's More > Testing > Simulated Harvest Run toggle. Release builds do not compile the simulator or its controls. The supplied GPX contains one return-leg discontinuity (`47.7900`); the fixture corrects it to the matching outbound latitude (`47.6900`). The resulting supplied geometry is approximately 18.1 km, even though the source name describes a half marathon.

### Debug Group Run Simulation

In a Debug build, open activity setup > Group run > Start test group to add three local mock runners. Start a simulated run to move their pins alongside the local run location and try the runner strip, map focus, and stop controls. The fixture bypasses the live group API and is compiled out of Release builds.

For a scheduled Group activity, the same setup also shows **Simulate attendees**. It seeds three nearby runners and one remote runner about 15 km away, linked to the event so the scheduled-attendee management UI is exercised. Start a simulated run, then select the remote runner in the strip to check distant-location focus. This fixture is local-only and bypasses the event live-map API.

Run the automated local server E2E test with one seeded persona. The runner starts the local API and embedded PostgreSQL, resets deterministic seed data, obtains a first-party session from the debug-only endpoint, then verifies authenticated account, activity, and social API state:

```sh
./scripts/run-local-e2e.sh new
./scripts/run-local-e2e.sh active
./scripts/run-local-e2e.sh social
```

API and database ports can be overridden with `OUTBOUND_E2E_API_PORT` and `OUTBOUND_E2E_DATABASE_PORT`. The script refuses occupied ports and prints its temporary log directory on completion. This command tests the real local first-party session boundary; simulator UI tests remain separate.

The Active Runner seed attaches three running photos to `Easy neighborhood run`. Each photo includes a deterministic distance and the matching coordinate from the seeded route so Activity Detail renders its thumbnail at the captured point on the map.

The simulator ID above is the current available `iPhone 17` simulator used for stable UI test runs. If that simulator disappears, rerun `xcodebuild` once to inspect the available destination list and refresh this doc.

## Device Build And Install

Preferred shortcut:

```sh
./scripts/build-install-bruce-main.sh
```

Build once and install the same signed app on every available paired iPhone:

```sh
./scripts/build-install-bruce-main.sh --all-devices
./scripts/build-install-bruce-main.sh --all-devices --launch
```

`--all-devices` discovers physical iPhones through CoreDevice before building,
including USB and local-network connections. It skips unpaired, unavailable,
and connecting phones; simulators, iPads, and Apple Watches are not direct install
targets. CoreDevice can omit `reality` for physical phones; discovery accepts that
while excluding simulator markers. `available (paired)` phones with USB or
local-network transport are eligible even before their developer tunnel connects.
Discovery reads the current `properties` JSON fields with legacy-field fallback.
If no eligible phones are found, it exits before building. Device names
and IDs are printed before the build. `CORE_DEVICE_ID` and `TARGET_DEVICE_NAME`
are ignored in this mode. It requires `python3` to read CoreDevice's JSON inventory.

Every target phone must be covered by the development provisioning profiles and
have Developer Mode enabled. Unlock the phones when using `--launch`. The helper
attempts each phone in turn, continues after an install or launch failure, prints
installed/launched totals and failure details, and exits nonzero if any attempted
operation fails. `INSTALL_TIMEOUT` applies separately to each install and device
launch. Phones that disconnect during the build can therefore fail individually.

The existing Social and Debug launch flags also apply to every target phone.
`--all-devices` cannot be combined with `--simulator` or `--build-only`.

Target the first available iPhone simulator instead:

```sh
./scripts/build-install-bruce-main.sh --simulator --launch
```

Set `SIMULATOR_ID` to select a specific simulator. The helper boots it when
needed, installs the app, and launches it without requiring Xcode.

The helper now prints timestamped phase logs and streams `xcodebuild` output, so if it appears slow you can see whether it is still in the build, device-check, install, or launch step.
For install builds, it reports missing local signing inputs and still runs `xcodebuild -allowProvisioningUpdates` so Xcode can refresh certificates and provisioning profiles from the signed-in account.
Before installing, it saves the installable app at `/tmp/outbound-latest-build/Debug-iphoneos/Outbound.app` or `/tmp/outbound-latest-build/Debug-iphonesimulator/Outbound.app`. It still deletes the full temporary DerivedData directory on exit. Device installation fails after 120 seconds instead of waiting indefinitely; set `INSTALL_TIMEOUT` to change this limit.
If `xcrun devicectl list devices` shows `Bruce main` as `connecting`, the helper stops before installing. Unlock the phone and connect it to the Mac by USB, then rerun once CoreDevice shows it as available. A paired device can still have a stalled local-network tunnel.

To reinstall the most recent existing build without rebuilding:

```sh
./scripts/reinstall-latest-ios.sh --main
./scripts/reinstall-latest-ios.sh --emulator
```

The reinstall helper checks the saved app, active temporary builds, and Xcode's Outbound DerivedData, then selects the newest compatible Debug app. It installs over the existing app to preserve local data. Add `--launch` to open it afterward, `--app /path/to/Outbound.app` to select a specific build, or `--reset` to uninstall first and delete local app data. Set `SIMULATOR_ID` to choose a specific emulator.

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

To send events from the launched app to Firebase Analytics DebugView with minimal delay:

```sh
./scripts/build-install-bruce-main.sh --launch --analytics-debug
```

Add `--simulator` to use a simulator. `--analytics-debug` requires `--launch` and passes
Firebase's `-FIRDebugEnabled` app argument. Debug mode persists for that development device
until the app is launched once with `-FIRDebugDisabled`, including from an Xcode scheme.
Use Firebase Console → Analytics → DebugView to inspect the events and their parameters.

To launch on `Bruce main` with the Debug test-persona picker connected to the local API's first-party session endpoint:

```sh
./scripts/build-install-bruce-main.sh --launch --with-test-personas
```

For Simulator, add `--simulator`; the helper uses localhost automatically:

```sh
./scripts/build-install-bruce-main.sh --simulator --launch --with-test-personas
```

When `--with-test-personas` is present, the helper reuses or starts the local backend stack, including
embedded PostgreSQL on port `54329` and the API on port `3000`. Persona seeding
remains explicit because it resets deterministic test data. Production startup rejects the debug-persona flag.
If it finds this repository's stale local API without its embedded database,
the helper stops that stale API gracefully and restarts the complete stack. It
does not stop unrelated processes occupying the required ports.

The helper detects the Mac's LAN address from `en0` or `en1` and passes it to
the app. Set `OUTBOUND_LOCAL_HOST` explicitly if the phone must use a different
reachable address. The phone and Mac must be on a network that permits local
device connections.

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
  --timeout 120 \
  /tmp/outbound-latest-build/Debug-iphoneos/Outbound.app
```

Optional launch, only when the phone is unlocked:

```sh
xcrun devicectl device process launch \
  --device 591E461F-4950-5FBD-A797-4777F1E83532 \
  plainstride.outbound
```

## Focused Group Recording Recovery UI Test

Run only when UI tests are requested:

```sh
./scripts/run-group-recovery-ui-test.sh
# Optional result directory (must not already contain GroupRecovery.xcresult):
./scripts/run-group-recovery-ui-test.sh /tmp/outbound-group-recovery-results
```

The runner creates and removes a dedicated iPhone simulator and serves synthetic attendees/live-map membership on loopback port 18763. Keep that port free. The Debug setup flag supplies a group intent and indoor setup only; the test starts and pauses a real recorder, then terminates and relaunches twice without the setup flag. It does not seed the recovery journal, use run simulation, or call production APIs.

Assertions cover the retained event title, exactly one assistant button, five attendee pills, sharing status, and Stop sharing after each restart. `GroupRecovery.xcresult` keeps restart screenshots; `fixture.log` confirms reads of the original live-map session after relaunch. No personal activity is saved. The focused `GroupRecoveryUI` scheme excludes unrelated unit-test targets; existing broad UI tests are not run.

Verified on iPhone 17 Pro / iOS 26.5 Simulator: one initial join, two app restarts, two reads of the same live-map session, with all group UI assertions passing. This covers recordings started by the current build; older journals without group context cannot reconstruct it.
