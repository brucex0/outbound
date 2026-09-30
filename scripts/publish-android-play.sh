#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ROOT_DIR}/android"
PACKAGE_ID="com.plainstride.outbound"
PLAY_API="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_ID}"
UPLOAD_API="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PACKAGE_ID}"
TRACK="closed"
VERSION_NAME="${PLAINSTRIDE_VERSION_NAME:-1.0}"
RELEASE_NOTES="${PLAINSTRIDE_RELEASE_NOTES:-Closed testing build.}"
PUBLISH=0
VERSION_CODE="${PLAINSTRIDE_VERSION_CODE:-}"

usage() {
  cat <<'EOF'
Usage: scripts/publish-android-play.sh [options]

Build a signed phone app bundle and optionally publish it to Google Play.

Options:
  --track closed|internal|production  Destination track (default: closed)
  --version-name NAME                 User-facing version (default: 1.0)
  --version-code CODE                 Set the monotonically increasing Play code
  --release-notes TEXT                English release notes
  --publish                           Upload and roll out to the selected track
  --help                              Show this help

Without --publish, the script performs a signed bundle build only. Publishing
uses the Android Publisher OAuth scope. Set
`PLAINSTRIDE_PLAY_SERVICE_ACCOUNT_JSON` to a protected service-account JSON
file, or use the active gcloud account. Signing credentials come from the
`PLAINSTRIDE_ANDROID_*` environment variables or existing macOS Keychain items.
EOF
}

while (($#)); do
  case "$1" in
    --track)
      [[ $# -ge 2 ]] || { echo "--track requires a value" >&2; exit 2; }
      TRACK="$2"
      shift 2
      ;;
    --version-name)
      [[ $# -ge 2 ]] || { echo "--version-name requires a value" >&2; exit 2; }
      VERSION_NAME="$2"
      shift 2
      ;;
    --version-code)
      [[ $# -ge 2 ]] || { echo "--version-code requires a value" >&2; exit 2; }
      VERSION_CODE="$2"
      shift 2
      ;;
    --release-notes)
      [[ $# -ge 2 ]] || { echo "--release-notes requires a value" >&2; exit 2; }
      RELEASE_NOTES="$2"
      shift 2
      ;;
    --publish)
      PUBLISH=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$TRACK" in
  closed) API_TRACK="alpha" ;;
  internal) API_TRACK="internal" ;;
  production) API_TRACK="production" ;;
  *) echo "Unsupported track: ${TRACK}" >&2; exit 2 ;;
esac

export PLAINSTRIDE_ANDROID_KEYSTORE_PATH="${PLAINSTRIDE_ANDROID_KEYSTORE_PATH:-${HOME}/.config/plainstride/android-upload.jks}"
export PLAINSTRIDE_ANDROID_KEY_ALIAS="${PLAINSTRIDE_ANDROID_KEY_ALIAS:-plainstride-upload}"

if [[ -z "${PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD:-}" ]]; then
  PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD="$(security find-generic-password -a "${USER}" -s plainstride-android-upload-store -w 2>/dev/null || true)"
  export PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD
fi
if [[ -z "${PLAINSTRIDE_ANDROID_KEY_PASSWORD:-}" ]]; then
  PLAINSTRIDE_ANDROID_KEY_PASSWORD="$(security find-generic-password -a "${USER}" -s plainstride-android-upload-key -w 2>/dev/null || true)"
  export PLAINSTRIDE_ANDROID_KEY_PASSWORD
fi

required_signing_variables=(
  PLAINSTRIDE_ANDROID_KEYSTORE_PATH
  PLAINSTRIDE_ANDROID_KEYSTORE_PASSWORD
  PLAINSTRIDE_ANDROID_KEY_ALIAS
  PLAINSTRIDE_ANDROID_KEY_PASSWORD
)
for variable_name in "${required_signing_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "Missing required signing setting: ${variable_name}" >&2
    exit 1
  fi
done
if [[ ! -f "$PLAINSTRIDE_ANDROID_KEYSTORE_PATH" ]]; then
  echo "Upload keystore not found: ${PLAINSTRIDE_ANDROID_KEYSTORE_PATH}" >&2
  exit 1
fi

if [[ -z "$VERSION_CODE" ]]; then
  if ((PUBLISH)); then
    echo "Set PLAINSTRIDE_VERSION_CODE or pass --version-code before publishing." >&2
    exit 1
  else
    VERSION_CODE=1
    echo "Build-only run defaults to version code 1; pass --version-code for another build." >&2
  fi
fi

if ! [[ "$VERSION_CODE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Version code must be a positive integer." >&2
  exit 2
fi
if [[ -z "$VERSION_NAME" ]]; then
  echo "Version name must not be empty." >&2
  exit 2
fi

export PLAINSTRIDE_VERSION_CODE="$VERSION_CODE"
export PLAINSTRIDE_VERSION_NAME="$VERSION_NAME"

echo "Building signed Android bundle (version ${VERSION_NAME}, code ${VERSION_CODE})..."
(
  cd "$ANDROID_DIR"
  ./gradlew --no-configuration-cache :app:verifyPlayReleaseConfiguration :app:bundleRelease
)

BUNDLE_PATH="${ANDROID_DIR}/app/build/outputs/bundle/release/app-release.aab"
if [[ ! -f "$BUNDLE_PATH" ]]; then
  echo "Expected Android App Bundle was not produced: ${BUNDLE_PATH}" >&2
  exit 1
fi
SIGNATURE_REPORT="$(jarsigner -verify "$BUNDLE_PATH" 2>&1)" || {
  echo "The Android App Bundle signature did not verify: ${SIGNATURE_REPORT}" >&2
  exit 1
}
if [[ "$SIGNATURE_REPORT" != *"jar verified."* ]]; then
  echo "The Android App Bundle is not signed: ${SIGNATURE_REPORT}" >&2
  exit 1
fi
echo "Signed bundle verified: ${BUNDLE_PATH}"

if ((!PUBLISH)); then
  echo "Build complete. Re-run with --publish --track ${TRACK} to upload it."
  exit 0
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plainstride-play-publish.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
chmod 700 "$TEMP_DIR"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is required to obtain an Android Publisher access token." >&2
  exit 1
fi
if [[ -n "${PLAINSTRIDE_PLAY_SERVICE_ACCOUNT_JSON:-}" ]]; then
  if [[ ! -f "$PLAINSTRIDE_PLAY_SERVICE_ACCOUNT_JSON" ]]; then
    echo "Play service-account JSON file not found." >&2
    exit 1
  fi
  GCLOUD_CONFIG="${TEMP_DIR}/gcloud"
  mkdir -m 700 "$GCLOUD_CONFIG"
  CLOUDSDK_CONFIG="$GCLOUD_CONFIG" gcloud auth activate-service-account \
    --key-file="$PLAINSTRIDE_PLAY_SERVICE_ACCOUNT_JSON" --quiet >/dev/null
  ACCESS_TOKEN="$(CLOUDSDK_CONFIG="$GCLOUD_CONFIG" gcloud auth print-access-token \
    --scopes=https://www.googleapis.com/auth/androidpublisher 2>/dev/null)" || {
    echo "The configured Play service account could not obtain an access token." >&2
    exit 1
  }
else
  ACCESS_TOKEN="$(gcloud auth print-access-token --scopes=https://www.googleapis.com/auth/androidpublisher 2>/dev/null)" || {
    echo "No gcloud account can access the Android Publisher API." >&2
    exit 1
  }
fi

AUTH_CONFIG="${TEMP_DIR}/curl-auth.conf"
printf 'header = "Authorization: Bearer %s"\n' "$ACCESS_TOKEN" > "$AUTH_CONFIG"
chmod 600 "$AUTH_CONFIG"
unset ACCESS_TOKEN

api_request() {
  local method="$1"
  local url="$2"
  local body_file="${3:-}"
  local args=(--silent --show-error --fail --config "$AUTH_CONFIG" --request "$method" --header 'Content-Type: application/json')
  if [[ -n "$body_file" ]]; then
    args+=(--data-binary "@${body_file}")
  fi
  curl "${args[@]}" "$url"
}

EMPTY_JSON="${TEMP_DIR}/empty.json"
printf '{}\n' > "$EMPTY_JSON"
EDIT_JSON="$(api_request POST "${PLAY_API}/edits" "$EMPTY_JSON")"
EDIT_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$EDIT_JSON")"

cleanup_edit() {
  if [[ -n "${EDIT_ID:-}" ]]; then
    curl --silent --show-error --config "$AUTH_CONFIG" --request DELETE "${PLAY_API}/edits/${EDIT_ID}" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup_edit; rm -rf "$TEMP_DIR"' EXIT

UPLOAD_JSON="$(curl --silent --show-error --fail --config "$AUTH_CONFIG" \
  --request POST \
  --header 'Content-Type: application/octet-stream' \
  --data-binary "@${BUNDLE_PATH}" \
  "${UPLOAD_API}/edits/${EDIT_ID}/bundles?uploadType=media")"
UPLOADED_VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["versionCode"])' <<<"$UPLOAD_JSON")"
if [[ "$UPLOADED_VERSION" != "$VERSION_CODE" ]]; then
  echo "Play received version code ${UPLOADED_VERSION}; expected ${VERSION_CODE}." >&2
  exit 1
fi

TRACK_BODY="${TEMP_DIR}/track.json"
python3 - "$API_TRACK" "$VERSION_CODE" "$VERSION_NAME" "$RELEASE_NOTES" "$TRACK_BODY" <<'PY'
import json
import sys

track, version_code, version_name, notes, output = sys.argv[1:]
body = {
    "track": track,
    "releases": [{
        "name": version_name,
        "versionCodes": [version_code],
        "status": "completed",
        "releaseNotes": [{"language": "en-US", "text": notes}],
    }],
}
with open(output, "w", encoding="utf-8") as file:
    json.dump(body, file)
PY

api_request PUT "${PLAY_API}/edits/${EDIT_ID}/tracks/${API_TRACK}" "$TRACK_BODY" >/dev/null
api_request POST "${PLAY_API}/edits/${EDIT_ID}:validate" >/dev/null
api_request POST "${PLAY_API}/edits/${EDIT_ID}:commit" >/dev/null
EDIT_ID=""
echo "Published version ${VERSION_NAME} (${VERSION_CODE}) to the ${TRACK} track."
