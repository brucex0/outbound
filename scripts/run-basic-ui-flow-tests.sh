#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
destination="${1:-}"
derived_data_path="/tmp/plainstride-basic-ui-flow-tests-derived"
timeout_seconds=600

if [[ -z "$destination" ]]; then
  simulator_id=$(xcrun simctl list devices available | awk '
    /iPhone/ && /(Booted|Shutdown)/ {
      for (field = 1; field <= NF; field++) {
        if ($field ~ /^\([0-9A-F-]{36}\)$/) {
          gsub(/[()]/, "", $field)
          print $field
          exit
        }
      }
    }
  ')
  [[ -n "$simulator_id" ]] || { print "No available iPhone simulator was found." >&2; exit 1; }
  destination="id=$simulator_id"
fi

if [[ "$destination" == id=* ]]; then
  simulator_id=${destination#id=}
  xcrun simctl uninstall "$simulator_id" plainstride.outbound >/dev/null 2>&1 || true
  # The freestyle start exercises the real permission flow (fresh install ->
  # in-app modal -> system prompt -> grant -> auto-resume), so permission is
  # intentionally not pre-granted. A GPS fix still has to be supplied
  # externally since simulators have no real sky: the default fix keeps the
  # gate's freshness check deterministic.
  xcrun simctl location "$simulator_id" set 37.3346,-122.0090 >/dev/null 2>&1 || true
fi

print "Running basic Plainstride UI flows on $destination (10-minute limit)..."
cd "$repo_dir"

xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 90 \
  -maximum-test-execution-time-allowance 120 \
  -only-testing:OutboundUITests/OutboundUITests/testLaunchSkipsLoginAndShowsPrimaryTabs \
  -only-testing:OutboundUITests/OutboundUITests/testPrimaryNavigationAndSettings \
  -only-testing:OutboundUITests/OutboundUITests/testTodayFreestyleStartOpensRecordingFlowAndCanFinish \
  test &
test_pid=$!

(
  sleep "$timeout_seconds"
  if kill -0 "$test_pid" >/dev/null 2>&1; then
    print "Basic UI flows exceeded 10 minutes; stopping xcodebuild." >&2
    kill -TERM "$test_pid" >/dev/null 2>&1 || true
  fi
) &
watchdog_pid=$!

set +e
wait "$test_pid"
test_status=$?
set -e

kill "$watchdog_pid" >/dev/null 2>&1 || true
wait "$watchdog_pid" >/dev/null 2>&1 || true
exit "$test_status"
