#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/outbound-device-derived}"
TARGET_DEVICE_NAME="${TARGET_DEVICE_NAME:-Bruce main}"
CORE_DEVICE_ID="${CORE_DEVICE_ID:-591E461F-4950-5FBD-A797-4777F1E83532}"
BUNDLE_ID="xhstudio.Outbound"

build_only=false
launch_after_install=false

usage() {
  cat <<USAGE
Usage: $0 [--build-only] [--launch]

Build and install Outbound on Bruce main.

Options:
  --build-only   Build the app without installing it.
  --launch       Launch the app after installing. Phone must be unlocked.
  -h, --help     Show this help.

Environment:
  DERIVED_DATA_PATH  Defaults to /tmp/outbound-device-derived.
  TARGET_DEVICE_NAME Defaults to Bruce main.
  CORE_DEVICE_ID     Defaults to Bruce main's current CoreDevice ID.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only)
      build_only=true
      ;;
    --launch)
      launch_after_install=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

echo "Building Outbound for Bruce main..."
xcodebuild -quiet -allowProvisioningUpdates \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme Outbound \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/Outbound.app"

if [[ "$build_only" == true ]]; then
  echo "Build complete: ${APP_PATH}"
  exit 0
fi

if ! xcrun devicectl list devices --hide-headers | grep -Fq "$CORE_DEVICE_ID"; then
  echo "Configured CoreDevice ID not currently available: ${CORE_DEVICE_ID}" >&2
  echo "Set CORE_DEVICE_ID to the current identifier for ${TARGET_DEVICE_NAME} from:" >&2
  echo "  xcrun devicectl list devices" >&2
  exit 1
fi

echo "Installing Outbound on Bruce main..."
xcrun devicectl device install app \
  --device "$CORE_DEVICE_ID" \
  "$APP_PATH"

if [[ "$launch_after_install" == true ]]; then
  echo "Launching Outbound on Bruce main..."
  xcrun devicectl device process launch \
    --device "$CORE_DEVICE_ID" \
    "$BUNDLE_ID"
fi

echo "Done."
