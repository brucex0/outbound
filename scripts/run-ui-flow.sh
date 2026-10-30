#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
flow=${1:---list}
case "$flow" in
  --list|--help)
    print 'Usage: scripts/run-ui-flow.sh FLOW [XCODE_DESTINATION]'
    print 'Flows: appearance, appearance-palette, activity-photos'
    print 'Default: temporary iPhone simulator. Physical device: platform=iOS,id=DEVICE_UDID'
    print 'Results: fresh /tmp/plainstride-ui-flow.XXXXXX directory (log + xcresult screenshots).'
    print 'Optional OUTBOUND_UI_SIMULATOR_RUNTIME selects the runtime for a temporary simulator.'
    exit 0 ;;
  activity-photos) test_name='SavedActivityPhotoUITests' ;;
  appearance) test_name='UIFlowTests/testAppearanceTipOpensChooserAndKeepsToolbarVisible' ;;
  appearance-palette) test_name='UIFlowTests/testAppearancePaletteOpensChooserWhileTipVisible' ;;
  *) print -u2 "Unknown UI flow: $flow. Use --list."; exit 2 ;;
esac
(( $# <= 2 )) || { print -u2 'Too many arguments. Use --help.'; exit 2; }

destination=${2:-}
if [[ "$flow" == activity-photos && -n "$destination" && "$destination" != platform=iOS\ Simulator,* ]]; then
  print -u2 'activity-photos requires an iOS Simulator (synthetic camera fixture).'
  exit 2
fi
results_dir=$(mktemp -d /tmp/plainstride-ui-flow.XXXXXX)
simulator_id=''
cleanup() {
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || print -u2 "Could not remove temporary simulator $simulator_id"
  fi
  print "UI flow results: $results_dir"
}
trap cleanup EXIT

if [[ -z "$destination" ]]; then
  simulator_options=("Plainstride UI Flow $flow" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
  if [[ -n "${OUTBOUND_UI_SIMULATOR_RUNTIME:-}" ]]; then
    simulator_options+=("$OUTBOUND_UI_SIMULATOR_RUNTIME")
  fi
  simulator_id=$(xcrun simctl create "${simulator_options[@]}")
  destination="platform=iOS Simulator,id=$simulator_id"
fi
build_options=()
if [[ "$destination" == platform=iOS,* ]]; then
  build_options+=(-allowProvisioningUpdates)
else
  build_options+=(CODE_SIGNING_ALLOWED=NO)
fi

if [[ "$flow" == activity-photos ]]; then
  # Retain XCTest results/screenshots without a potentially stalled sysdiagnose.
  build_options+=(-collect-test-diagnostics never)
fi

print "Running $flow on $destination"
cd "$repo_dir"
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "$destination" \
  -derivedDataPath /tmp/plainstride-ui-flow-derived \
  -resultBundlePath "$results_dir/Flow.xcresult" \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  "-only-testing:OutboundUITests/$test_name" \
  "${build_options[@]}" test 2>&1 | tee "$results_dir/xcodebuild.log"

print "UI flow passed: $flow"
