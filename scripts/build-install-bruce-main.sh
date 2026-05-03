#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH"
else
  DERIVED_DATA_PATH="$(mktemp -d /tmp/outbound-device-derived.XXXXXX)"
fi
TARGET_DEVICE_NAME="${TARGET_DEVICE_NAME:-Bruce main}"
CORE_DEVICE_ID="${CORE_DEVICE_ID:-591E461F-4950-5FBD-A797-4777F1E83532}"
BUNDLE_ID="xhstudio.Outbound"

build_only=false
launch_after_install=false

timestamp() {
  date '+%H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

trap 'log "Failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

run_with_prefix() {
  local prefix="$1"
  shift

  "$@" 2>&1 | while IFS= read -r line; do
    printf '[%s] %s %s\n' "$(timestamp)" "${prefix}" "${line}"
  done
}

usage() {
  cat <<USAGE
Usage: $0 [--build-only] [--launch]

Build and install Outbound on Bruce main.

Options:
  --build-only   Build the app without installing it.
  --launch       Launch the app after installing. Phone must be unlocked.
  -h, --help     Show this help.

Environment:
  DERIVED_DATA_PATH  Optional. Defaults to a fresh temp directory under /tmp.
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

log "Starting build helper for ${TARGET_DEVICE_NAME}"
log "DerivedData: ${DERIVED_DATA_PATH}"
log "CoreDevice ID: ${CORE_DEVICE_ID}"
if [[ "$build_only" == true ]]; then
  log "Mode: build only"
else
  mode_description="build and install"
  if [[ "$launch_after_install" == true ]]; then
    mode_description="${mode_description}, then launch"
  fi
  log "Mode: ${mode_description}"
fi

log "Building Outbound for ${TARGET_DEVICE_NAME}..."
run_with_prefix "[build]" xcodebuild -allowProvisioningUpdates \
  -project ios/Outbound/Outbound.xcodeproj \
  -scheme Outbound \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -showBuildTimingSummary \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/Outbound.app"
log "Build finished"
log "App path: ${APP_PATH}"

if [[ "$build_only" == true ]]; then
  log "Build complete"
  exit 0
fi

log "Checking device availability..."
if ! xcrun devicectl list devices --hide-headers | grep -Fq "$CORE_DEVICE_ID"; then
  echo "Configured CoreDevice ID not currently available: ${CORE_DEVICE_ID}" >&2
  echo "Set CORE_DEVICE_ID to the current identifier for ${TARGET_DEVICE_NAME} from:" >&2
  echo "  xcrun devicectl list devices" >&2
  exit 1
fi

log "Installing Outbound on ${TARGET_DEVICE_NAME}..."
run_with_prefix "[install]" xcrun devicectl device install app \
  --device "$CORE_DEVICE_ID" \
  "$APP_PATH"

if [[ "$launch_after_install" == true ]]; then
  log "Launching Outbound on ${TARGET_DEVICE_NAME}..."
  run_with_prefix "[launch]" xcrun devicectl device process launch \
    --device "$CORE_DEVICE_ID" \
    "$BUNDLE_ID"
fi

log "Done."
