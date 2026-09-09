#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ROOT_DIR}/android"
APK_PATH="${ANDROID_DIR}/app/build/outputs/apk/release/app-release.apk"
PACKAGE_ID="com.plainstride.outbound"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Library/Android/sdk}}"

export PLAINSTRIDE_ANDROID_KEYSTORE_PATH="${PLAINSTRIDE_ANDROID_KEYSTORE_PATH:-${HOME}/.config/plainstride/android-upload.jks}"
export PLAINSTRIDE_ANDROID_KEY_ALIAS="${PLAINSTRIDE_ANDROID_KEY_ALIAS:-plainstride-upload}"
export PLAINSTRIDE_VERSION_CODE="${PLAINSTRIDE_VERSION_CODE:-1}"
export PLAINSTRIDE_VERSION_NAME="${PLAINSTRIDE_VERSION_NAME:-1.0}"

if [[ -z "${PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD:-}" ]]; then
  PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD="$(security find-generic-password -a "${USER}" -s plainstride-android-upload-store -w 2>/dev/null || true)"
  export PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD
fi
if [[ -z "${PLAINSTRIDE_ANDROID_KEY_PASSWORD:-}" ]]; then
  PLAINSTRIDE_ANDROID_KEY_PASSWORD="$(security find-generic-password -a "${USER}" -s plainstride-android-upload-key -w 2>/dev/null || true)"
  export PLAINSTRIDE_ANDROID_KEY_PASSWORD
fi

if [[ -d "${SDK_ROOT}/platform-tools" ]]; then
  export PATH="${SDK_ROOT}/platform-tools:${PATH}"
fi
if [[ -d "${SDK_ROOT}/build-tools/36.0.0" ]]; then
  export PATH="${SDK_ROOT}/build-tools/36.0.0:${PATH}"
fi

required_signing_variables=(
  PLAINSTRIDE_ANDROID_KEYSTORE_PATH
  PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD
  PLAINSTRIDE_ANDROID_KEY_ALIAS
  PLAINSTRIDE_ANDROID_KEY_PASSWORD
  PLAINSTRIDE_VERSION_CODE
  PLAINSTRIDE_VERSION_NAME
)

for variable_name in "${required_signing_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required environment variable: ${variable_name}" >&2
    if [[ "$variable_name" == PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD || "$variable_name" == PLAINSTRIDE_ANDROID_KEY_PASSWORD ]]; then
      echo "The expected Plainstride upload credential was not found in macOS Keychain." >&2
    fi
    exit 1
  fi
done

if [[ ! -f "$PLAINSTRIDE_ANDROID_KEYSTORE_PATH" ]]; then
  echo "Keystore not found: ${PLAINSTRIDE_ANDROID_KEYSTORE_PATH}" >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is not on PATH. Add the Android SDK platform-tools directory to PATH." >&2
  exit 1
fi

if ! command -v apksigner >/dev/null 2>&1; then
  echo "apksigner is not on PATH. Add Android SDK build-tools to PATH." >&2
  exit 1
fi

connected_devices="$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
if [[ "$connected_devices" -eq 0 ]]; then
  echo "No authorized Android device is connected." >&2
  exit 1
fi
if [[ "$connected_devices" -gt 1 && -z "${ANDROID_SERIAL:-}" ]]; then
  echo "Multiple Android devices are connected. Set ANDROID_SERIAL to select one." >&2
  exit 1
fi

echo "Building signed Plainstride release APK..."
(
  cd "$ANDROID_DIR"
  ./gradlew --no-configuration-cache :app:verifyPlayReleaseConfiguration :app:assembleRelease
)

if [[ ! -f "$APK_PATH" ]]; then
  echo "Expected APK was not produced: ${APK_PATH}" >&2
  exit 1
fi

echo "Verifying APK signature..."
apksigner verify --verbose --print-certs "$APK_PATH"

echo "Installing ${PACKAGE_ID}..."
adb install -r "$APK_PATH"

echo "Installed signed release APK: ${APK_PATH}"
