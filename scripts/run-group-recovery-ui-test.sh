#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$(mktemp -d /tmp/outbound-group-recovery.XXXXXX)}"
mkdir -p "$output_dir"
simulator_id=""
cleanup() {
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
runtime_id="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(sorted(r,key=lambda x: tuple(map(int,x["version"].split("."))))[-1]["identifier"])')"
simulator_id="$(xcrun simctl create "Outbound Recovery UI Test" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime_id")"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
cd "$repo_root"
xcodebuild -quiet -project ios/Outbound/Outbound.xcodeproj -scheme GroupRecoveryUI \
  -destination "id=$simulator_id" -parallel-testing-enabled NO -collect-test-diagnostics never \
  -derivedDataPath /tmp/outbound-group-recovery-ui-derived \
  -clonedSourcePackagesDirPath /tmp/outbound-groups-source-packages \
  -packageCachePath /tmp/outbound-package-cache \
  -resultBundlePath "$output_dir/GroupRecovery.xcresult" \
  -only-testing:OutboundUITests/GroupRecoveryUITests CODE_SIGNING_ALLOWED=NO test \
  > "$output_dir/xcodebuild.log" 2>&1
printf 'Recovery UI test passed. Results: %s\n' "$output_dir"
