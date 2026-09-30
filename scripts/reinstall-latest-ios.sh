#!/usr/bin/env bash
set -euo pipefail

CORE_DEVICE_ID="${CORE_DEVICE_ID:-591E461F-4950-5FBD-A797-4777F1E83532}"
SIMULATOR_ID="${SIMULATOR_ID:-}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-120}"
BUNDLE_ID="plainstride.outbound"
CACHED_BUILD_ROOT="/tmp/outbound-latest-build"

target=main
launch_after_install=false
reset_app=false
app_override=""

usage() {
  cat <<USAGE
Usage: $0 [--main|--emulator] [--app PATH] [--launch] [--reset]

Reinstall the newest existing iOS build without rebuilding.

Options:
  --main             Install on Bruce main (default).
  --emulator          Install on the first available iPhone Simulator.
  --simulator         Alias for --emulator.
  --app PATH          Use a specific Outbound.app instead of auto-detecting.
  --launch            Launch the app after installation.
  --reset             Uninstall first, deleting the app's local data.
  -h, --help          Show this help.

Environment:
  CORE_DEVICE_ID      Override Bruce main's CoreDevice ID.
  SIMULATOR_ID        Select a specific simulator with --emulator.
  INSTALL_TIMEOUT     Device command timeout in seconds (default: 120).

Auto-detection checks the build helper's retained app, its active temporary
builds, and Xcode's Outbound DerivedData. Device builds must be signed.
USAGE
}

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

run_with_prefix() {
  local prefix="$1"
  shift
  "$@" 2>&1 | sed -u "s/^/${prefix} /"
}

detect_simulator_id() {
  xcrun simctl list devices available | awk '
    /iPhone/ && /(Booted|Shutdown)/ {
      for (field = 1; field <= NF; field++) {
        if ($field ~ /^\([0-9A-Fa-f-]{36}\)$/) {
          gsub(/[()]/, "", $field)
          print $field
          exit
        }
      }
    }
  '
}

usable_app() {
  local candidate="$1"
  local bundle_id
  local platform

  [[ -d "$candidate" && -f "$candidate/Info.plist" ]] || return 1
  bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Info.plist" 2>/dev/null)" || return 1
  platform="$(plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$candidate/Info.plist" 2>/dev/null)" || return 1
  [[ "$bundle_id" == "$BUNDLE_ID" && "$platform" == "$expected_platform" ]] || return 1
  if [[ "$target" == main ]]; then
    codesign --verify "$candidate" >/dev/null 2>&1 || return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main)
      target=main
      ;;
    --emulator|--simulator)
      target=emulator
      ;;
    --app)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--app requires a path to Outbound.app." >&2
        exit 2
      fi
      app_override="$2"
      shift
      ;;
    --launch)
      launch_after_install=true
      ;;
    --reset)
      reset_app=true
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

if [[ ! "$INSTALL_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "INSTALL_TIMEOUT must be a positive number of seconds." >&2
  exit 2
fi

if [[ "$target" == main ]]; then
  product_directory=Debug-iphoneos
  expected_platform=iPhoneOS
else
  product_directory=Debug-iphonesimulator
  expected_platform=iPhoneSimulator
fi

if [[ -n "$app_override" ]]; then
  app_path="$app_override"
  if ! usable_app "$app_path"; then
    echo "The selected app is missing, built for another target, or unsigned: $app_path" >&2
    exit 1
  fi
else
  shopt -s nullglob
  candidates=("$CACHED_BUILD_ROOT/$product_directory/Outbound.app")
  for derived_dir in /tmp/outbound-device-derived.* "$HOME"/Library/Developer/Xcode/DerivedData/Outbound-*; do
    candidates+=("$derived_dir/Build/Products/$product_directory/Outbound.app")
  done

  app_path=""
  latest_timestamp=-1
  for candidate in "${candidates[@]}"; do
    usable_app "$candidate" || continue
    timestamp="$(stat -f %m "$candidate/Info.plist")"
    if (( timestamp > latest_timestamp )); then
      latest_timestamp="$timestamp"
      app_path="$candidate"
    fi
  done

  if [[ -z "$app_path" ]]; then
    if [[ "$target" == emulator ]]; then
      echo "No installable emulator build found. Run ./scripts/build-install-bruce-main.sh --simulator and retry." >&2
    else
      echo "No installable device build found. Run ./scripts/build-install-bruce-main.sh and retry." >&2
    fi
    echo "You can also pass an existing app bundle with --app PATH." >&2
    exit 1
  fi
fi

log "Using build: $app_path"

if [[ "$target" == emulator ]]; then
  if [[ -z "$SIMULATOR_ID" ]]; then
    SIMULATOR_ID="$(detect_simulator_id)"
  fi
  if [[ -z "$SIMULATOR_ID" ]]; then
    echo "No available iPhone simulator was found." >&2
    exit 1
  fi
  simulator_state="$(xcrun simctl list devices | awk -v id="$SIMULATOR_ID" 'index($0, id) { print; exit }')"
  if [[ -z "$simulator_state" ]]; then
    echo "Configured simulator is unavailable: $SIMULATOR_ID" >&2
    exit 1
  fi
  if [[ "$simulator_state" != *"(Booted)"* ]]; then
    log "Booting simulator $SIMULATOR_ID..."
    run_with_prefix "[boot]" xcrun simctl boot "$SIMULATOR_ID"
  fi
  run_with_prefix "[boot]" xcrun simctl bootstatus "$SIMULATOR_ID" -b
  if [[ "$reset_app" == true ]]; then
    log "Removing installed app and its local data from simulator..."
    run_with_prefix "[uninstall]" xcrun simctl uninstall "$SIMULATOR_ID" "$BUNDLE_ID"
  fi
  log "Installing Outbound on simulator $SIMULATOR_ID..."
  run_with_prefix "[install]" xcrun simctl install "$SIMULATOR_ID" "$app_path"
  if [[ "$launch_after_install" == true ]]; then
    log "Launching Outbound..."
    run_with_prefix "[launch]" xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID"
  fi
else
  if [[ "$reset_app" == true ]]; then
    log "Removing installed app and its local data from Bruce main..."
    run_with_prefix "[uninstall]" xcrun devicectl device uninstall app \
      --device "$CORE_DEVICE_ID" --timeout "$INSTALL_TIMEOUT" "$BUNDLE_ID"
  fi
  log "Installing Outbound on Bruce main (timeout: ${INSTALL_TIMEOUT}s)..."
  run_with_prefix "[install]" xcrun devicectl device install app \
    --device "$CORE_DEVICE_ID" --timeout "$INSTALL_TIMEOUT" "$app_path"
  if [[ "$launch_after_install" == true ]]; then
    log "Launching Outbound..."
    run_with_prefix "[launch]" xcrun devicectl device process launch \
      --device "$CORE_DEVICE_ID" --timeout "$INSTALL_TIMEOUT" "$BUNDLE_ID"
  fi
fi

log "Done."
