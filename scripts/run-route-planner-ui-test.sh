#!/usr/bin/env bash
# Run only with explicit authorization for simulator UI regression checks.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/outbound-route-planner-ui.XXXXXX)}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
runtime_id="${OUTBOUND_UI_SIMULATOR_RUNTIME:-$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and any(d["identifier"] == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" for d in x.get("supportedDeviceTypes", []))]; print(sorted(r,key=lambda x: tuple(map(int,x["version"].split("."))))[-1]["identifier"])')}"
simulator_id="$(xcrun simctl create "Outbound Route Planner UI" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime_id")"
printf '%s\n' "$simulator_id" > "$output_dir/simulator-id.txt"
completed=no
cleanup() {
  if [[ "$completed" == yes && "${OUTBOUND_UI_KEEP_SIMULATOR:-NO}" != YES ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  else
    printf 'Preserved simulator %s and results in %s.\n' "$simulator_id" "$output_dir" >&2
    if [[ "$completed" != yes ]]; then
      printf 'Investigate failures in a fresh session and separate simulator.\n' >&2
    fi
  fi
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b > "$output_dir/boot.log" 2>&1
xcrun simctl location "$simulator_id" set 47.6101,-122.2015
cd "$repo_root"
xcodebuild -quiet -jobs 2 -project ios/Outbound/Outbound.xcodeproj -scheme RoutePlannerUI \
  -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath "${OUTBOUND_UI_DERIVED_DATA:-$output_dir/DerivedData}" \
  -packageCachePath "$output_dir/package-cache" \
  -resultBundlePath "$output_dir/RoutePlanner.xcresult" \
  -only-testing:OutboundUITests/LoopPlannerPresentationUITests \
  OUTBOUND_APP_TEST_MODE=YES CODE_SIGNING_ALLOWED=NO test > "$output_dir/xcodebuild.log" 2>&1
completed=yes
printf 'Route planner UI regression passed. Results: %s\n' "$output_dir"
