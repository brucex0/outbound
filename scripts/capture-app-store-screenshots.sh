#!/usr/bin/env bash
# Capture production views with existing synthetic fixtures; never runs XCTest.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SIMULATOR_ID:?Set SIMULATOR_ID to an installed iPhone simulator}"
OUTPUT_DIR="${1:-$ROOT_DIR/artifacts/app-store-screenshots/current/raw}"
mkdir -p "$OUTPUT_DIR"
common=(
  -AppleLanguages '(en)' -AppleLocale en_US
  -OutboundScreenshotCapture -OutboundDisableFirebase -OutboundSkipOnboarding -OutboundUITestSeedData -OutboundUseMockMusic
  -OutboundAPIBaseURL http://127.0.0.1:18764
  '-new_user_onboarding_completed_v2.UI test session' YES
  -home_widget_onboarding_seen_v1 YES -push_notification_permission_primer_seen_v1 YES
  -theme_discovery_tip_dismissed_v1 YES
)
for tip in theme_discovery activity_overflow music_discovery cheer_me_on voice_guide shoes swipe_to_map save_route; do
  common+=("-tooltip.$tip.dismissed.v1" YES)
done
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui "$SIMULATOR_ID" appearance light
xcrun simctl privacy "$SIMULATOR_ID" grant location plainstride.outbound
xcrun simctl location "$SIMULATOR_ID" set 37.7696,-122.4863
capture() {
  local name="$1"
  shift
  # No running process before the first capture is expected.
  xcrun simctl terminate "$SIMULATOR_ID" plainstride.outbound >/dev/null 2>&1 || true
  xcrun simctl launch "$SIMULATOR_ID" plainstride.outbound "${common[@]}" "$@"
  # MapKit tiles and async local fixture loading must settle before capture.
  sleep "${CAPTURE_SETTLE_SECONDS:-12}"
  xcrun simctl io "$SIMULATOR_ID" screenshot --mask=black "$OUTPUT_DIR/$name.png"
}
capture 01-start -OutboundScreenshotScreen today
capture 02-live-run -OutboundScreenshotLiveRun -OutboundUITestLive10K
capture 03-progress -OutboundScreenshotScreen progress
capture 04-trends -OutboundScreenshotScreen trends
capture 05-records -OutboundScreenshotScreen records
capture 06-live-sharing -OutboundDebugLiveCheerFollower
capture 07-community-routes -OutboundDebugCommunityRoutes
capture 08-social -OutboundScreenshotScreen social
capture 09-activity-detail -OutboundScreenshotScreen detail
