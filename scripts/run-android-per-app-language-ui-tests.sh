#!/usr/bin/env bash
# Focused Android UI coverage for system per-app language selection (Android 13+).
#
# Builds and installs the debug APK plus the instrumented test APK, runs the
# UiAutomator suite that drives the real Settings "App language" screen for
# English, Spanish, Simplified Chinese, and System default, then pulls the
# screenshots and scenario log. Packages are installed with adb directly so the
# artifacts in the app's data directory survive the run.
#
# Requires: JDK 17, ANDROID_HOME, adb, one connected Android 13+ device or
# emulator. Set ANDROID_SERIAL when more than one device is attached. The debug
# app must be signed out (the localized sign-in surface is asserted); this
# script never clears app data.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$repo_dir/android"
out_dir="${OUT_DIR:-$android_dir/app/build/outputs/per-app-language-ui}"
debug_package="com.plainstride.outbound.debug"
test_package="com.plainstride.outbound.navigationtest"
test_runner="androidx.test.runner.AndroidJUnitRunner"
test_class="com.plainstride.outbound.PerAppLanguageUiTest"

export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
adb="$ANDROID_HOME/platform-tools/adb"

if [[ ! -x "$adb" ]]; then
  echo "adb not found at $adb; set ANDROID_HOME." >&2
  exit 1
fi

if [[ -z "${ANDROID_SERIAL:-}" ]]; then
  serials=$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  serial_count=$(printf '%s\n' "$serials" | grep -c . || true)
  if [[ "$serial_count" -ne 1 ]]; then
    echo "Set ANDROID_SERIAL to the one device to test (found $serial_count attached)." >&2
    exit 1
  fi
  ANDROID_SERIAL="$serials"
fi

sdk=$("$adb" -s "$ANDROID_SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')
model=$("$adb" -s "$ANDROID_SERIAL" shell getprop ro.product.model | tr -d '\r')
if [[ -z "$sdk" || "$sdk" -lt 33 ]]; then
  echo "Per-app language UI tests need Android 13+ (API 33+); $ANDROID_SERIAL reports API $sdk." >&2
  exit 1
fi

echo "Per-app language UI tests on $ANDROID_SERIAL ($model, API $sdk)"
echo "Before: device=$("$adb" -s "$ANDROID_SERIAL" shell cmd locale get-device-locale | tr -d '\r') app=$("$adb" -s "$ANDROID_SERIAL" shell cmd locale get-app-locales "$debug_package" | tr -d '\r')"

restore_system_default() {
  "$adb" -s "$ANDROID_SERIAL" shell cmd locale set-app-locales "$debug_package" >/dev/null 2>&1 || true
  "$adb" -s "$ANDROID_SERIAL" shell am force-stop "$debug_package" >/dev/null 2>&1 || true
}
trap restore_system_default EXIT

rm -rf "$out_dir"
mkdir -p "$out_dir"

echo "Building the debug app and instrumented test APKs..."
(cd "$android_dir" && ./gradlew --quiet :app:assembleDebug :app:assembleNavigationTest :app:assembleNavigationTestAndroidTest --max-workers=2 --no-parallel)

app_apk="$android_dir/app/build/outputs/apk/debug/app-debug.apk"
target_apk="$android_dir/app/build/outputs/apk/navigationTest/app-navigationTest.apk"
test_apk="$android_dir/app/build/outputs/apk/androidTest/navigationTest/app-navigationTest-androidTest.apk"
for apk in "$app_apk" "$target_apk" "$test_apk"; do
  if [[ ! -f "$apk" ]]; then
    echo "Expected APK not found: $apk" >&2
    exit 1
  fi
done

echo "Installing $debug_package, the instrumentation target app, and the test APK..."
"$adb" -s "$ANDROID_SERIAL" install -r "$app_apk" >/dev/null
"$adb" -s "$ANDROID_SERIAL" install -r "$target_apk" >/dev/null
"$adb" -s "$ANDROID_SERIAL" install -r "$test_apk" >/dev/null

echo "Clearing previous artifacts on device..."
"$adb" -s "$ANDROID_SERIAL" shell run-as "$test_package" rm -rf "files/per-app-language-ui"

echo "Running $test_class..."
set +e
"$adb" -s "$ANDROID_SERIAL" shell am instrument -w \
  -e class "$test_class" \
  "$test_package.test/$test_runner" | tee "$out_dir/instrumentation.txt"
instrument_status=${PIPESTATUS[0]}
set -e

echo "Pulling screenshots and scenario log..."
# The test APK's data lives in the target app package, which is debuggable.
"$adb" -s "$ANDROID_SERIAL" exec-out run-as "$test_package" tar -C "/data/data/$test_package/files" -cf - per-app-language-ui \
  | tar -xf - -C "$out_dir"

echo "After: app=$("$adb" -s "$ANDROID_SERIAL" shell cmd locale get-app-locales "$debug_package" | tr -d '\r') device=$("$adb" -s "$ANDROID_SERIAL" shell cmd locale get-device-locale | tr -d '\r')"
echo "Artifacts: $out_dir/per-app-language-ui"
echo "Scenario log: $out_dir/per-app-language-ui/results.txt"
exit "$instrument_status"
