#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/redeploy-live-coach-voices.sh [extra gcloud run deploy flags]

Verifies the published live-coach pack, deploys a no-traffic Cloud Run
candidate with the current production coaching configuration, checks the
candidate health endpoint, and then moves production traffic to it.

Environment overrides:
  PROJECT_ID                       default: outbound-494602
  REGION                           default: us-central1
  SERVICE                          default: outbound-api
  LIVE_COACH_CATALOG_VERSION       default: 2026-08-30.1
  LIVE_COACH_AUDIO_BUCKET          default: PROJECT_ID-live-coach-audio
  LIVE_COACH_ENABLED_LOCALES       default: en,zh-Hans
  LIVE_COACH_AUDIO_PUBLIC_BASE_URL default: Google Cloud Storage public URL
  CANDIDATE_TAG                    default: live-coach-voice-candidate
  RUN_MANIFEST_CHECK=0             skip the published-manifest preflight

The production defaults intentionally retain dynamic coaching at 100%, the
Gemini start planner, the 1.5-second provider deadline, and founding/trial
access. Override individual LIVE_COACH_* variables only for a deliberate
configuration change.
USAGE
  exit 0
fi

PROJECT_ID="${PROJECT_ID:-outbound-494602}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-outbound-api}"
GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
CANDIDATE_TAG="${CANDIDATE_TAG:-live-coach-voice-candidate}"
LIVE_COACH_CATALOG_VERSION="${LIVE_COACH_CATALOG_VERSION:-2026-08-30.1}"
LIVE_COACH_AUDIO_BUCKET="${LIVE_COACH_AUDIO_BUCKET:-$PROJECT_ID-live-coach-audio}"
LIVE_COACH_AUDIO_PUBLIC_BASE_URL="${LIVE_COACH_AUDIO_PUBLIC_BASE_URL:-https://storage.googleapis.com/$LIVE_COACH_AUDIO_BUCKET}"
LIVE_COACH_ENABLED_LOCALES="${LIVE_COACH_ENABLED_LOCALES:-en,zh-Hans}"
LIVE_COACH_ENABLED_VOICE_PROFILES="${LIVE_COACH_ENABLED_VOICE_PROFILES:-plainstride_warm_1,plainstride_clear_1}"
LIVE_COACH_AUDIO_MANIFEST_URL="${LIVE_COACH_AUDIO_MANIFEST_URL:-$LIVE_COACH_AUDIO_PUBLIC_BASE_URL/live-coach/$LIVE_COACH_CATALOG_VERSION/manifest.json}"
LIVE_COACH_AUDIO_ASSET_BASE_URL="${LIVE_COACH_AUDIO_ASSET_BASE_URL:-$LIVE_COACH_AUDIO_PUBLIC_BASE_URL/live-coach/$LIVE_COACH_CATALOG_VERSION/assets}"
RUN_MANIFEST_CHECK="${RUN_MANIFEST_CHECK:-1}"

# These are the approved production live-coach settings. Keeping them here
# prevents the minimal-cost defaults in deploy-backend-gcloud.sh from silently
# disabling the planner, dynamic audio, or warm instance during a voice deploy.
CLOUD_RUN_MIN_INSTANCES="${CLOUD_RUN_MIN_INSTANCES:-1}"
CLOUD_RUN_MAX_INSTANCES="${CLOUD_RUN_MAX_INSTANCES:-3}"
LIVE_COACH_SERVER_AUDIO_MODE="${LIVE_COACH_SERVER_AUDIO_MODE:-dynamic}"
LIVE_COACH_ACCESS_MODE="${LIVE_COACH_ACCESS_MODE:-founding_trial}"
LIVE_COACH_CONFIG_VERSION="${LIVE_COACH_CONFIG_VERSION:-2}"
LIVE_COACH_ENABLED_PERSONAS="${LIVE_COACH_ENABLED_PERSONAS:-plainstride_supportive_v1,plainstride_focused_v1}"
LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT="${LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT:-100}"
LIVE_COACH_FOUNDING_USER_LIMIT="${LIVE_COACH_FOUNDING_USER_LIMIT:-1000}"
LIVE_COACH_TRIAL_RUN_LIMIT="${LIVE_COACH_TRIAL_RUN_LIMIT:-3}"
LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE="${LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE:-8}"
LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME="${LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME:-15}"
LIVE_COACH_CUE_VALIDITY_MILLISECONDS="${LIVE_COACH_CUE_VALIDITY_MILLISECONDS:-5000}"
LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS="${LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS:-1500}"
LIVE_COACH_PLANNER_ENABLED="${LIVE_COACH_PLANNER_ENABLED:-true}"
GEMINI_LIVE_COACH_PLANNER_MODEL="${GEMINI_LIVE_COACH_PLANNER_MODEL:-gemini-3.1-pro-preview}"
GEMINI_VERTEX_PROJECT_ID="${GEMINI_VERTEX_PROJECT_ID:-$PROJECT_ID}"
GEMINI_VERTEX_LOCATION="${GEMINI_VERTEX_LOCATION:-global}"
GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS="${GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS:-20000}"
LIVE_COACH_AUDIO_PACK_PUBLISHED="${LIVE_COACH_AUDIO_PACK_PUBLISHED:-true}"
GOOGLE_CLOUD_TTS_ENABLED="${GOOGLE_CLOUD_TTS_ENABLED:-true}"
GOOGLE_CLOUD_TTS_API_ENDPOINT="${GOOGLE_CLOUD_TTS_API_ENDPOINT:-us-texttospeech.googleapis.com}"
GOOGLE_CLOUD_TTS_ENDPOINT_KEY="${GOOGLE_CLOUD_TTS_ENDPOINT_KEY:-google-cloud-tts-us}"
GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION="${GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION:-us}"
ALIBABA_AI_ENABLED="${ALIBABA_AI_ENABLED:-false}"
AI_ROUTE_POLICY_VERSION="${AI_ROUTE_POLICY_VERSION:-2}"

if [[ ! -x "$GCLOUD_BIN" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  else
    echo "gcloud was not found. Set GCLOUD_BIN=/path/to/gcloud." >&2
    exit 1
  fi
fi
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "node was not found. Set NODE_BIN=/path/to/node." >&2
  exit 1
fi
if [[ ! "$CANDIDATE_TAG" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
  echo "CANDIDATE_TAG must be a lowercase Cloud Run tag." >&2
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
if [[ "$LIVE_COACH_AUDIO_PACK_PUBLISHED" != "true" ]]; then
  echo "Voice redeploy requires LIVE_COACH_AUDIO_PACK_PUBLISHED=true." >&2
  exit 1
fi

manifest_file="$(mktemp "${TMPDIR:-/tmp}/plainstride-live-coach-manifest.XXXXXX")"
trap 'rm -f "$manifest_file"' EXIT
if [[ "$RUN_MANIFEST_CHECK" != "0" ]]; then
  echo "Checking published voice manifest: $LIVE_COACH_AUDIO_MANIFEST_URL"
  curl --fail --silent --show-error "$LIVE_COACH_AUDIO_MANIFEST_URL" --output "$manifest_file"
  "$NODE_BIN" "$ROOT_DIR/scripts/verify-live-coach-audio-manifest.mjs" \
    --manifest "$manifest_file" \
    --catalog "$ROOT_DIR/backend/resources/liveCoachAudio/catalog.v1.json" \
    --public-keys-plist "$ROOT_DIR/ios/Outbound/SupportFiles/Info.plist" \
    --version "$LIVE_COACH_CATALOG_VERSION" \
    --locales "$LIVE_COACH_ENABLED_LOCALES" \
    --voices "$LIVE_COACH_ENABLED_VOICE_PROFILES"
fi

export PROJECT_ID REGION SERVICE GCLOUD_BIN NODE_BIN
export CLOUD_RUN_MIN_INSTANCES CLOUD_RUN_MAX_INSTANCES
export LIVE_COACH_CATALOG_VERSION LIVE_COACH_ENABLED_LOCALES
export LIVE_COACH_ENABLED_PERSONAS LIVE_COACH_ENABLED_VOICE_PROFILES
export LIVE_COACH_SERVER_AUDIO_MODE LIVE_COACH_ACCESS_MODE
export LIVE_COACH_CONFIG_VERSION LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT
export LIVE_COACH_FOUNDING_USER_LIMIT LIVE_COACH_TRIAL_RUN_LIMIT
export LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME
export LIVE_COACH_CUE_VALIDITY_MILLISECONDS LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS
export LIVE_COACH_PLANNER_ENABLED GEMINI_LIVE_COACH_PLANNER_MODEL
export GEMINI_VERTEX_PROJECT_ID GEMINI_VERTEX_LOCATION
export GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS
export LIVE_COACH_AUDIO_PACK_PUBLISHED LIVE_COACH_AUDIO_MANIFEST_URL LIVE_COACH_AUDIO_ASSET_BASE_URL
export GOOGLE_CLOUD_TTS_ENABLED GOOGLE_CLOUD_TTS_API_ENDPOINT
export GOOGLE_CLOUD_TTS_ENDPOINT_KEY GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION
export ALIBABA_AI_ENABLED AI_ROUTE_POLICY_VERSION
export RUN_HEALTH_CHECK=0

"$ROOT_DIR/scripts/deploy-backend-gcloud.sh" --no-traffic "$@"

candidate_revision="$("$GCLOUD_BIN" run services describe "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  --format='value(status.latestCreatedRevisionName)')"
if [[ -z "$candidate_revision" ]]; then
  echo "Cloud Run did not report a candidate revision." >&2
  exit 1
fi

echo "Tagging candidate revision $candidate_revision"
"$GCLOUD_BIN" run services update-traffic "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  "--update-tags=$CANDIDATE_TAG=$candidate_revision" \
  --quiet

candidate_url="$(
  "$GCLOUD_BIN" run services describe "$SERVICE" \
    "--project=$PROJECT_ID" \
    "--region=$REGION" \
    --format=json |
    "$NODE_BIN" --input-type=module -e '
      let raw = "";
      for await (const chunk of process.stdin) raw += chunk;
      const tag = process.argv[1];
      const service = JSON.parse(raw);
      const target = (service.status?.traffic ?? []).find((entry) => entry.tag === tag);
      if (!target?.url) process.exit(1);
      process.stdout.write(target.url);
    ' "$CANDIDATE_TAG"
)"
if [[ -z "$candidate_url" ]]; then
  echo "Cloud Run did not report the candidate tag URL." >&2
  exit 1
fi

echo "Checking candidate: $candidate_url/health"
curl --fail --silent --show-error \
  --retry 5 \
  --retry-all-errors \
  --retry-delay 5 \
  "$candidate_url/health"
echo

echo "Moving production traffic to $candidate_revision"
"$GCLOUD_BIN" run services update-traffic "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  "--to-revisions=$candidate_revision=100" \
  --clear-tags \
  --quiet

service_url="$("$GCLOUD_BIN" run services describe "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  --format='value(status.url)')"
echo "Checking production: $service_url/health"
curl --fail --silent --show-error \
  --retry 5 \
  --retry-all-errors \
  --retry-delay 5 \
  "$service_url/health"
echo
echo "Published live-coach catalog $LIVE_COACH_CATALOG_VERSION is active on $candidate_revision."
