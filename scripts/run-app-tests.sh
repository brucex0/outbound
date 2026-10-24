#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
destination="${1:-}"
owned_simulator=""
result_dir=$(mktemp -d /tmp/plainstride-app-tests.XXXXXX)

cleanup() {
  if [[ -n "$owned_simulator" ]]; then
    xcrun simctl shutdown "$owned_simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$owned_simulator" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "$destination" ]]; then
  owned_simulator=$(xcrun simctl create "Plainstride App Tests" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
  destination="platform=iOS Simulator,id=$owned_simulator"
elif [[ "$destination" == id=* ]]; then
  destination="platform=iOS Simulator,$destination"
fi
[[ "$destination" == "platform=iOS Simulator,"* ]] || { print -u2 "Use an iPhone simulator destination."; exit 1; }

print "Running all Plainstride UI tests on $destination"
print "Results: $result_dir/AppTests.xcresult"
cd "$repo_dir"
xcodebuild -quiet -jobs 2 \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "$destination" \
  -derivedDataPath /tmp/plainstride-app-tests-derived \
  -resultBundlePath "$result_dir/AppTests.xcresult" \
  OUTBOUND_APP_TEST_MODE=YES CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -only-testing:OutboundUITests \
  test
