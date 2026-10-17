#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
destination="${1:-}"
owned_simulator=""
result_dir=$(mktemp -d /tmp/plainstride-watch-flows.XXXXXX)

cleanup() {
  if [[ -n "$owned_simulator" ]]; then
    xcrun simctl shutdown "$owned_simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$owned_simulator" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "$destination" ]]; then
  owned_simulator=$(xcrun simctl create "Plainstride Watch Flow Tests" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
  destination="platform=iOS Simulator,id=$owned_simulator"
fi

[[ "$destination" == "platform=iOS Simulator,"* ]] || { print -u2 "Use an iPhone simulator destination."; exit 1; }

print "Running simulated Watch / phone-only flows on $destination"
print "Results: $result_dir/WatchFlows.xcresult"
cd "$repo_dir"
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "$destination" \
  -derivedDataPath /tmp/plainstride-watch-flow-derived \
  -resultBundlePath "$result_dir/WatchFlows.xcresult" \
  OUTBOUND_APP_TEST_MODE=YES \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:OutboundUITests/WatchWorkoutFlowUITests \
  test
