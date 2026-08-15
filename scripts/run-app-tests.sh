#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
destination="${1:-}"
derived_data_path="/tmp/plainstride-app-tests-derived"

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
fi

print "Running full Plainstride app regression suite on $destination..."
cd "$repo_dir"
xcodebuild -quiet \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme OutboundAppTests \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  OUTBOUND_APP_TEST_MODE=YES \
  -parallel-testing-enabled NO \
  -only-testing:OutboundUITests/OutboundUITests/testLaunchSkipsLoginAndShowsPrimaryTabs \
  -only-testing:OutboundUITests/OutboundUITests/testPrimaryNavigationAndSettings \
  -only-testing:OutboundUITests/OutboundUITests/testSeededSocialFeedRunAndComments \
  -only-testing:OutboundUITests/OutboundUITests/testSeededSocialConnectionsGroupsAndNotifications \
  -only-testing:OutboundUITests/OutboundUITests/testSeededSocialDeclinesConnectionRequest \
  -only-testing:OutboundUITests/OutboundUITests/testTodayFreestyleStartOpensRecordingFlowAndCanFinish \
  -only-testing:OutboundUITests/OutboundUITests/testLaunchPerformance \
  test
