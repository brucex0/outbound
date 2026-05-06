# Build, Test, Signing, And Device Notes

Open this when validating changes, installing on device, editing signing settings, or debugging simulator/device execution.

## Signing And Entitlements

- Bundle ID: `xhstudio.Outbound`.
- Development team in the project: `JGNGM4YRX5`.
- Current iOS deployment target in Xcode: `18.0`.
- Debug device builds use `ios/Outbound/SupportFiles/OutboundDebug.entitlements`, which is intentionally empty so personal-team installs can still work.
- Release builds use `ios/Outbound/SupportFiles/Outbound.entitlements`, which includes Sign in with Apple (`com.apple.developer.applesignin`).
- Use a paid Apple Developer team before validating Apple provider sign-in on device or shipping.
- Do not re-add `aps-environment`, `com.apple.developer.healthkit`, or `com.apple.developer.healthkit.access` unless switching to a paid team that supports Push Notifications and HealthKit.
- Device installs still require an Apple Development identity and iOS Development provisioning profiles for both `xhstudio.Outbound` and `xhstudio.Outbound.OutboundLiveActivityExtension`.
- To refresh signing in Xcode: open `ios/Outbound/Outbound.xcodeproj`, go to Xcode Settings > Accounts, select the Apple ID for team `JGNGM4YRX5`, use Manage Certificates to create an Apple Development certificate if needed, then select both the `Outbound` app target and `OutboundLiveActivityExtension` target and keep Automatically manage signing enabled with team `JGNGM4YRX5`.
- If Xcode offers to register `Bruce main` or create/download provisioning profiles during the next build, allow it.

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

This project previously hit an Xcode state where old `Blueprint.xcscmblueprint` metadata still referenced removed packages such as `piper-objc`, which caused indexing and package resolution to hang.

Build without installing:

```sh
./scripts/build-install-bruce-main.sh --build-only
```

This mode disables code signing with `CODE_SIGNING_ALLOWED=NO`, so it is useful for compile validation even when Xcode is not signed into an Apple Developer account. The output app is not installable on a physical device.

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
  xhstudio.Outbound
```
