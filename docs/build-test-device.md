# Build, Test, Signing, And Device Notes

Open this when validating changes, installing on device, editing signing settings, or debugging simulator/device execution.

## Signing And Entitlements

- Bundle ID: `xhstudio.Outbound`.
- Development team in the project: `JGNGM4YRX5`.
- Personal-team installs currently require empty entitlements.
- Do not re-add `aps-environment`, `com.apple.developer.healthkit`, or `com.apple.developer.healthkit.access` unless switching to a paid team that supports Push Notifications and HealthKit.

## Device IDs

- User device name: `Bruce main`.
- Xcode device ID: `00008150-000A1194026A401C`.
- CoreDevice ID: `591E461F-4950-5FBD-A797-4777F1E83532`.
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
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'id=90811627-0921-4CE9-A934-5B8E6614EF6D' -parallel-testing-enabled NO test
swift test
```

The simulator ID above is the available `iPhone 17` simulator used for stable UI test runs. The user's earlier Xcode simulator destination was `iPhone 17 Pro` with ID `C91E235E-94B0-4CA7-B41E-46F170AA4554`.

## Device Build And Install

Preferred shortcut:

```sh
./scripts/build-install-bruce-main.sh
```

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
xcodebuild -quiet -allowProvisioningUpdates \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme Outbound \
  -destination 'id=00008150-000A1194026A401C' \
  -derivedDataPath /tmp/outbound-device-derived build

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
