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
SIMULATOR_ID="${SIMULATOR_ID:-}"
BUNDLE_ID="plainstride.outbound"
EXTENSION_BUNDLE_ID="${BUNDLE_ID}.liveactivity"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-WT54K7D7VH}"
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

build_only=false
launch_after_install=false
enable_social=false
enable_test_personas=false
enable_analytics_debug=false
enable_simulated_run=false
target_simulator=false
local_development_host="${OUTBOUND_LOCAL_HOST:-}"

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
Usage: $0 [--simulator] [--build-only] [--launch] [--simulated-run] [--analytics-debug] [--with-test-personas] [--with-social|--without-social]

Build and install Outbound on Bruce main or an iOS Simulator.

Options:
  --simulator       Target an iOS Simulator instead of Bruce main.
  --build-only      Build the app without installing it.
  --launch          Launch the app after installing. Phone must be unlocked.
  --analytics-debug Enable Firebase Analytics DebugView for the launched app.
                    Requires --launch.
  --simulated-run   Preselect the DEBUG-only Redmond Harvest route simulator.
                    Requires --launch.
  --with-test-personas
                    Route a launched Debug app to the local API and enable its
                    first-party persona picker. Requires --launch.
  --with-social     Enable the Social tab with OUTBOUND_ENABLE_SOCIAL.
  --without-social  Disable Social tab. This is the default beta-safe build.
  -h, --help        Show this help.

Environment:
  DERIVED_DATA_PATH  Optional. Defaults to a fresh temp directory under /tmp.
  TARGET_DEVICE_NAME Defaults to Bruce main.
  CORE_DEVICE_ID     Defaults to Bruce main's current CoreDevice ID.
  SIMULATOR_ID       Optional simulator UUID. Defaults to the first available
                     iPhone simulator when --simulator is used.
  DEVELOPMENT_TEAM   Defaults to ${DEVELOPMENT_TEAM}.
  OTHER_SWIFT_FLAGS  Preserved when --with-social appends the Social flag.
  OUTBOUND_LOCAL_HOST
                      Mac LAN address reachable from the phone. Auto-detected
                      from en0 or en1 when --with-test-personas is used.
USAGE
}

detect_local_development_host() {
  local interface
  local detected_host

  for interface in en0 en1; do
    detected_host="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
    if [[ -n "$detected_host" ]]; then
      printf '%s\n' "$detected_host"
      return 0
    fi
  done

  return 1
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

start_local_backend_if_needed() {
  local api_url="http://127.0.0.1:3000/health"
  local backend_log="${TMPDIR:-/tmp}/plainstride-local-backend.log"
  local backend_job_label="plainstride.local-backend"
  local api_ready=false
  local database_ready=false

  if curl --silent --fail --max-time 1 "$api_url" >/dev/null 2>&1; then
    api_ready=true
  fi
  if nc -z 127.0.0.1 54329 >/dev/null 2>&1; then
    database_ready=true
  fi

  if [[ "$api_ready" == true && "$database_ready" == true ]]; then
    log "Local backend: already running"
    return 0
  fi

  if [[ "$api_ready" == true && "$database_ready" != true ]]; then
    local api_pid
    local api_command
    local api_working_directory

    api_pid="$(lsof -nP -t -iTCP:3000 -sTCP:LISTEN 2>/dev/null | head -n 1)"
    api_command="$(ps -p "$api_pid" -o command= 2>/dev/null || true)"
    api_working_directory="$(lsof -a -p "$api_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"

    if [[ -n "$api_pid" \
      && "$api_command" == *"node scripts/start-local-stack.mjs"* \
      && "$api_working_directory" == "$ROOT_DIR/backend" ]]; then
      log "Restarting stale local backend ${api_pid}; embedded PostgreSQL is unavailable..."
      kill -TERM "$api_pid"
      for _ in {1..15}; do
        if ! nc -z 127.0.0.1 3000 >/dev/null 2>&1; then
          api_ready=false
          break
        fi
        sleep 1
      done
      if [[ "$api_ready" == true ]]; then
        echo "The stale local backend did not stop cleanly. Stop process ${api_pid} and retry." >&2
        return 1
      fi
    fi
  fi

  if [[ "$api_ready" == true || "$database_ready" == true ]]; then
    echo "The local backend is only partially available on ports 3000 and 54329." >&2
    echo "Stop the existing local process and retry, or start the full stack manually." >&2
    return 1
  fi

  log "Starting embedded PostgreSQL and local API..."
  launchctl remove "$backend_job_label" >/dev/null 2>&1 || true
  launchctl submit -l "$backend_job_label" -- \
    /usr/bin/env "PATH=$PATH" \
    /bin/bash -c \
    'cd "$1" && exec env FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIREBASE_PROJECT_ID=outbound-494602 npm run start:local >>"$2" 2>&1' \
    _ "$ROOT_DIR/backend" "$backend_log"

  for _ in {1..180}; do
    if curl --silent --fail --max-time 1 "$api_url" >/dev/null 2>&1 \
      && nc -z 127.0.0.1 54329 >/dev/null 2>&1; then
      log "Local backend: ready (log: ${backend_log})"
      return 0
    fi
    if ! launchctl list "$backend_job_label" >/dev/null 2>&1; then
      echo "Local backend exited before becoming ready. See ${backend_log}." >&2
      return 1
    fi
    sleep 1
  done

  echo "Timed out waiting for the local backend. See ${backend_log}." >&2
  return 1
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
    --simulator)
      target_simulator=true
      ;;
    --build-only)
      build_only=true
      ;;
    --launch)
      launch_after_install=true
      ;;
    --with-test-personas)
      enable_test_personas=true
      ;;
    --analytics-debug)
      enable_analytics_debug=true
      ;;
    --simulated-run)
      enable_simulated_run=true
      ;;
    --with-social)
      enable_social=true
      ;;
    --without-social)
      enable_social=false
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

if [[ "$enable_test_personas" == true && "$launch_after_install" != true ]]; then
  echo "--with-test-personas requires --launch." >&2
  exit 2
fi

if [[ "$enable_analytics_debug" == true && "$launch_after_install" != true ]]; then
  echo "--analytics-debug requires --launch." >&2
  exit 2
fi

if [[ "$enable_simulated_run" == true && "$launch_after_install" != true ]]; then
  echo "--simulated-run requires --launch." >&2
  exit 2
fi

if [[ "$target_simulator" == true && "$build_only" != true && -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(detect_simulator_id)"
  if [[ -z "$SIMULATOR_ID" ]]; then
    echo "No available iPhone simulator was found." >&2
    exit 1
  fi
fi

if [[ "$enable_test_personas" == true && "$target_simulator" == true ]]; then
  local_development_host="127.0.0.1"
elif [[ "$enable_test_personas" == true && -z "$local_development_host" ]]; then
  local_development_host="$(detect_local_development_host || true)"
  if [[ -z "$local_development_host" ]]; then
    echo "Could not detect a Mac LAN address on en0 or en1." >&2
    echo "Set OUTBOUND_LOCAL_HOST to the address reachable from ${TARGET_DEVICE_NAME}." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR"

if [[ "$enable_test_personas" == true ]]; then
  start_local_backend_if_needed
fi

if [[ "$target_simulator" == true ]]; then
  target_description="iOS Simulator"
  [[ -z "$SIMULATOR_ID" ]] || target_description="iOS Simulator ${SIMULATOR_ID}"
else
  target_description="$TARGET_DEVICE_NAME"
fi

log "Starting build helper for ${target_description}"
log "DerivedData: ${DERIVED_DATA_PATH}"
if [[ "$target_simulator" == true ]]; then
  [[ -z "$SIMULATOR_ID" ]] || log "Simulator ID: ${SIMULATOR_ID}"
else
  log "CoreDevice ID: ${CORE_DEVICE_ID}"
fi
if [[ "$enable_social" == true ]]; then
  log "Social: enabled"
else
  log "Social: disabled"
fi
if [[ "$enable_test_personas" == true ]]; then
  log "Test personas: first-party debug sessions enabled"
  log "Local API: http://${local_development_host}:3000/v1"
fi
if [[ "$enable_analytics_debug" == true ]]; then
  log "Analytics: Firebase DebugView enabled"
fi
if [[ "$enable_simulated_run" == true ]]; then
  log "Run simulation: Redmond Harvest route preselected"
fi
if [[ "$build_only" == true ]]; then
  log "Mode: build only"
  log "Signing: disabled for compile-only validation"
else
  mode_description="build and install"
  if [[ "$launch_after_install" == true ]]; then
    mode_description="${mode_description}, then launch"
  fi
  log "Mode: ${mode_description}"
  if [[ "$target_simulator" == true ]]; then
    log "Signing: simulator"
  else
    log "Signing team: ${DEVELOPMENT_TEAM}"
    report_signing_inputs
  fi
fi

log "Building Outbound for ${target_description}..."
if [[ "$target_simulator" == true ]]; then
  build_destination='generic/platform=iOS Simulator'
  build_product_directory='Debug-iphonesimulator'
else
  build_destination='generic/platform=iOS'
  build_product_directory='Debug-iphoneos'
fi
build_args=(
  xcodebuild
  -project ios/Outbound/Outbound.xcodeproj
  -scheme Outbound
  -destination "$build_destination"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -showBuildTimingSummary
)

if [[ "$build_only" == true ]]; then
  build_args+=(CODE_SIGNING_ALLOWED=NO)
elif [[ "$target_simulator" != true ]]; then
  build_args+=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

if [[ "$enable_social" == true ]]; then
  social_swift_flags="${OTHER_SWIFT_FLAGS:-\$(inherited)} -D OUTBOUND_ENABLE_SOCIAL"
  build_args+=(OTHER_SWIFT_FLAGS="$social_swift_flags")
fi

build_args+=(build)

run_with_prefix "[build]" "${build_args[@]}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${build_product_directory}/Outbound.app"
log "Build finished"
log "App path: ${APP_PATH}"

if [[ "$build_only" == true ]]; then
  log "Build complete"
  exit 0
fi

if [[ "$target_simulator" == true ]]; then
  simulator_state="$(xcrun simctl list devices | awk -v id="$SIMULATOR_ID" 'index($0, id) { print; exit }')"
  if [[ -z "$simulator_state" ]]; then
    echo "Configured simulator is unavailable: ${SIMULATOR_ID}" >&2
    exit 1
  fi
  if [[ "$simulator_state" != *"(Booted)"* ]]; then
    log "Booting iOS Simulator ${SIMULATOR_ID}..."
    run_with_prefix "[boot]" xcrun simctl boot "$SIMULATOR_ID"
  fi
  run_with_prefix "[boot]" xcrun simctl bootstatus "$SIMULATOR_ID" -b
  log "Installing Outbound on iOS Simulator..."
  run_with_prefix "[install]" xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
else
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
fi

if [[ "$launch_after_install" == true ]]; then
  log "Launching Outbound on ${target_description}..."
  app_launch_args=()
  if [[ "$enable_analytics_debug" == true ]]; then
    app_launch_args+=(-FIRDebugEnabled)
  fi
  if [[ "$enable_test_personas" == true ]]; then
    app_launch_args+=(
      -OutboundEnableDebugPersonas
      -OutboundLocalAPIHost "$local_development_host"
      -OutboundAPIBaseURL "http://${local_development_host}:3000/v1"
    )
  fi
  if [[ "$enable_simulated_run" == true ]]; then
    app_launch_args+=(-OutboundSimulatedHarvestRun)
  fi

  if [[ "$target_simulator" == true ]]; then
    launch_args=(xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$BUNDLE_ID")
    launch_args+=("${app_launch_args[@]}")
  else
    launch_args=(
      xcrun devicectl device process launch
      --device "$CORE_DEVICE_ID"
    )
    if [[ ${#app_launch_args[@]} -gt 0 ]]; then
      launch_args+=(
        --terminate-existing
        "$BUNDLE_ID"
        --
      )
      launch_args+=("${app_launch_args[@]}")
    else
      launch_args+=("$BUNDLE_ID")
    fi
  fi
  run_with_prefix "[launch]" "${launch_args[@]}"
fi

log "Done."
