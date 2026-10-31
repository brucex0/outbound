#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${ANDROID_SERIAL:?Set ANDROID_SERIAL to a dedicated running emulator (for example emulator-5556).}"
case "$ANDROID_SERIAL" in emulator-*) ;; *) echo 'Navigation fixtures require a dedicated emulator.' >&2; exit 1 ;; esac
sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_dir" && -f local.properties ]]; then sdk_dir="$(sed -n 's/^sdk.dir=//p' local.properties)"; fi
adb_bin="${sdk_dir:?Set ANDROID_HOME or sdk.dir in local.properties}/platform-tools/adb"
"$adb_bin" -s "$ANDROID_SERIAL" get-state
./gradlew :app:assembleNavigationTest :app:assembleNavigationTestAndroidTest :feature:social:assembleDebugAndroidTest
"$adb_bin" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/navigationTest/app-navigationTest.apk
"$adb_bin" -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/androidTest/navigationTest/app-navigationTest-androidTest.apk
"$adb_bin" -s "$ANDROID_SERIAL" install -r feature/social/build/outputs/apk/androidTest/debug/social-debug-androidTest.apk
result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT
run_tests() {
    "$adb_bin" -s "$ANDROID_SERIAL" shell am instrument -w -r "$1" | tee "$result_file"
    # am instrument can return zero even when tests fail.
    rg -q '^OK \([0-9]+ tests?\)' "$result_file"
}
run_tests com.plainstride.outbound.navigationtest.test/androidx.test.runner.AndroidJUnitRunner
run_tests com.plainstride.outbound.feature.social.test/com.plainstride.outbound.feature.social.ProfileTestRunner
