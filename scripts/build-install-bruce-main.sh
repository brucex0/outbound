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
EXTENSION_BUNDLE_ID="${BUNDLE_ID}.OutboundLiveActivityExtension"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-JGNGM4YRX5}"
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

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

  "$@" 2>&1 | sed -u "s/^/${prefix} /"
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
  DEVELOPMENT_TEAM   Defaults to ${DEVELOPMENT_TEAM}.
USAGE
}

has_signing_identity_for_team() {
  security find-identity -p codesigning -v 2>/dev/null | grep -Eq "(Apple Development|iPhone Developer): .*\(${DEVELOPMENT_TEAM}\)"
}

has_profile_for_bundle() {
  local bundle_id="$1"
  local application_id
  local profile_dir
  local profile

  for profile_dir in "${PROFILE_DIRS[@]}"; do
    [[ -d "$profile_dir" ]] || continue
    while IFS= read -r -d '' profile; do
      application_id="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)"
      if [[ -z "$application_id" ]]; then
        application_id="$(plutil -extract Entitlements.application-identifier raw -o - "$profile" 2>/dev/null || true)"
      fi
      if [[ "$application_id" == "${DEVELOPMENT_TEAM}.${bundle_id}" ]]; then
        return 0
      fi
    done < <(find "$profile_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) -print0)
  done

  return 1
}

report_signing_inputs() {
  local missing=false

  log "Checking local signing inputs for team ${DEVELOPMENT_TEAM}..."

  if ! has_signing_identity_for_team; then
    echo "Missing Apple Development signing identity for team ${DEVELOPMENT_TEAM}." >&2
    missing=true
  fi

  if ! has_profile_for_bundle "$BUNDLE_ID"; then
    echo "Missing iOS Development provisioning profile for ${DEVELOPMENT_TEAM}.${BUNDLE_ID}." >&2
    missing=true
  fi

  if ! has_profile_for_bundle "$EXTENSION_BUNDLE_ID"; then
    echo "Missing iOS Development provisioning profile for ${DEVELOPMENT_TEAM}.${EXTENSION_BUNDLE_ID}." >&2
    missing=true
  fi

  if [[ "$missing" == true ]]; then
    echo "Continuing so xcodebuild -allowProvisioningUpdates can refresh signing from your Xcode account." >&2
    echo "If xcodebuild still reports No Accounts, refresh signing once in Xcode for the Outbound app and Live Activity extension targets." >&2
  else
    log "Local signing inputs found"
  fi
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
  log "Signing: disabled for compile-only validation"
else
  mode_description="build and install"
  if [[ "$launch_after_install" == true ]]; then
    mode_description="${mode_description}, then launch"
  fi
  log "Mode: ${mode_description}"
  log "Signing team: ${DEVELOPMENT_TEAM}"
  report_signing_inputs
fi

log "Building Outbound for ${TARGET_DEVICE_NAME}..."
build_args=(
  xcodebuild
  -project ios/Outbound/Outbound.xcodeproj
  -scheme Outbound
  -destination 'generic/platform=iOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
  -showBuildTimingSummary
)

if [[ "$build_only" == true ]]; then
  build_args+=(CODE_SIGNING_ALLOWED=NO)
else
  build_args+=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

build_args+=(build)

run_with_prefix "[build]" "${build_args[@]}"

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
