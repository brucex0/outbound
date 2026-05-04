# Build, Test, Signing, And Device Notes

Open this when validating changes, installing on device, editing signing settings, or debugging simulator/device execution.

## Signing And Entitlements

- Bundle ID: `xhstudio.Outbound`.
- Development team in the project: `JGNGM4YRX5`.
- Current iOS deployment target in Xcode: `18.0`.
- The app entitlement file includes Sign in with Apple (`com.apple.developer.applesignin`).
- Personal-team installs may fail for capabilities the team cannot provision. Use a paid Apple Developer team before validating provider sign-in on device or shipping.
- Do not re-add `aps-environment`, `com.apple.developer.healthkit`, or `com.apple.developer.healthkit.access` unless switching to a paid team that supports Push Notifications and HealthKit.

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
