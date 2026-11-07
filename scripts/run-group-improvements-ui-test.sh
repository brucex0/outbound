#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/outbound-group-improvements.XXXXXX)}"
mkdir -p "$output_dir"
simulator_id=""
cleanup() {
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
runtime_id="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and any(d["identifier"] == "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" for d in x.get("supportedDeviceTypes", []))]; print(sorted(r,key=lambda x: tuple(map(int,x["version"].split("."))))[-1]["identifier"])')"
simulator_id="$(xcrun simctl create "Outbound Group Improvements UI Test" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime_id")"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
cd "$repo_root"
xcodebuild -quiet -jobs 2 -project ios/Outbound/Outbound.xcodeproj -scheme GroupImprovementsUI \
  -destination "id=$simulator_id" -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath /tmp/outbound-group-improvements-ui-derived \
  -clonedSourcePackagesDirPath /tmp/outbound-group-improvements-source-packages \
  -packageCachePath /tmp/outbound-group-improvements-package-cache \
  -resultBundlePath "$output_dir/GroupImprovements.xcresult" \
  -only-testing:OutboundUITests/GroupImprovementsUITests OUTBOUND_APP_TEST_MODE=YES CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -D OUTBOUND_ENABLE_SOCIAL' test \
  > "$output_dir/xcodebuild.log" 2>&1
printf 'Group improvements UI tests passed. Results: %s\n' "$output_dir"
