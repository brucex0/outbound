#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/redeploy-live-coach-voices.sh [extra gcloud run deploy flags]

Redeploys the backend voice catalog while preserving the approved EN/ZH
fixed-audio pilot. The command verifies that the published manifest is
reachable, builds the backend, deploys it to Cloud Run, and checks /health.

Environment overrides:
  PROJECT_ID                       default: outbound-494602
  LIVE_COACH_CATALOG_VERSION       default: 2026-08-28.1-en-zh
  LIVE_COACH_AUDIO_BUCKET          default: PROJECT_ID-live-coach-audio
  LIVE_COACH_ENABLED_LOCALES       default: en,zh-Hans
  LIVE_COACH_AUDIO_PUBLIC_BASE_URL default: Google Cloud Storage public URL
  RUN_MANIFEST_CHECK=0             skip the published-manifest preflight

This command only permits fixed_only mode, a published pack, and a 0% dynamic
rollout. Use deploy-backend-gcloud.sh directly for an intentional rollout-mode
change.
USAGE
  exit 0
fi

PROJECT_ID="${PROJECT_ID:-outbound-494602}"
LIVE_COACH_CATALOG_VERSION="${LIVE_COACH_CATALOG_VERSION:-2026-08-28.1-en-zh}"
LIVE_COACH_AUDIO_BUCKET="${LIVE_COACH_AUDIO_BUCKET:-$PROJECT_ID-live-coach-audio}"
LIVE_COACH_AUDIO_PUBLIC_BASE_URL="${LIVE_COACH_AUDIO_PUBLIC_BASE_URL:-https://storage.googleapis.com/$LIVE_COACH_AUDIO_BUCKET}"
LIVE_COACH_ENABLED_LOCALES="${LIVE_COACH_ENABLED_LOCALES:-en,zh-Hans}"
LIVE_COACH_SERVER_AUDIO_MODE="${LIVE_COACH_SERVER_AUDIO_MODE:-fixed_only}"
LIVE_COACH_AUDIO_PACK_PUBLISHED="${LIVE_COACH_AUDIO_PACK_PUBLISHED:-true}"
LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT="${LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT:-0}"
LIVE_COACH_AUDIO_MANIFEST_URL="${LIVE_COACH_AUDIO_MANIFEST_URL:-$LIVE_COACH_AUDIO_PUBLIC_BASE_URL/live-coach/$LIVE_COACH_CATALOG_VERSION/manifest.json}"
LIVE_COACH_AUDIO_ASSET_BASE_URL="${LIVE_COACH_AUDIO_ASSET_BASE_URL:-$LIVE_COACH_AUDIO_PUBLIC_BASE_URL/live-coach/$LIVE_COACH_CATALOG_VERSION/assets}"
RUN_MANIFEST_CHECK="${RUN_MANIFEST_CHECK:-1}"

if [[ "$LIVE_COACH_SERVER_AUDIO_MODE" != "fixed_only" ]]; then
  echo "Voice redeploy requires LIVE_COACH_SERVER_AUDIO_MODE=fixed_only." >&2
  exit 1
fi
if [[ "$LIVE_COACH_AUDIO_PACK_PUBLISHED" != "true" ]]; then
  echo "Voice redeploy requires LIVE_COACH_AUDIO_PACK_PUBLISHED=true." >&2
  exit 1
fi
if [[ "$LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT" != "0" ]]; then
  echo "Voice redeploy requires LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT=0." >&2
  exit 1
fi
if [[ ! "$LIVE_COACH_AUDIO_MANIFEST_URL" =~ ^https:// ]]; then
  echo "LIVE_COACH_AUDIO_MANIFEST_URL must use HTTPS." >&2
  exit 1
fi
if [[ ! "$LIVE_COACH_AUDIO_ASSET_BASE_URL" =~ ^https:// ]]; then
  echo "LIVE_COACH_AUDIO_ASSET_BASE_URL must use HTTPS." >&2
  exit 1
fi

if [[ "$RUN_MANIFEST_CHECK" != "0" ]]; then
  echo "Checking published voice manifest: $LIVE_COACH_AUDIO_MANIFEST_URL"
  curl --fail --silent --show-error --output /dev/null "$LIVE_COACH_AUDIO_MANIFEST_URL"
fi

export PROJECT_ID
export LIVE_COACH_CATALOG_VERSION
export LIVE_COACH_ENABLED_LOCALES
export LIVE_COACH_SERVER_AUDIO_MODE
export LIVE_COACH_AUDIO_PACK_PUBLISHED
export LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT
export LIVE_COACH_AUDIO_MANIFEST_URL
export LIVE_COACH_AUDIO_ASSET_BASE_URL

exec "$ROOT_DIR/scripts/deploy-backend-gcloud.sh" "$@"
