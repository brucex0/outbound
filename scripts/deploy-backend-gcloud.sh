#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/deploy-backend-gcloud.sh [extra gcloud run deploy flags]

Deploys backend/ to Cloud Run using the Outbound defaults.

Environment overrides:
  PROJECT_ID              default: outbound-494602
  GCLOUD_ACCOUNT          default: bruce.xia74@gmail.com
  REGION                  default: us-central1
  SERVICE                 default: outbound-api
  RUNTIME_SERVICE_ACCOUNT default: outbound-api-runtime@PROJECT_ID.iam.gserviceaccount.com
  APPLE_CLIENT_ID         default: plainstride.outbound
  APPLE_TEAM_ID           default: WT54K7D7VH
  APPLE_KEY_ID            default: 8Z4P665DD3
  AUTH_ACCESS_KEY_ID      default: production-v1
  GOOGLE_AUTH_CLIENT_IDS  default: production Google OAuth client
  IOS_APP_STORE_URL       default: Plainstride's direct App Store listing
  CLOUD_SQL_INSTANCE      default: PROJECT_ID:REGION:outbound-db
  CLOUD_RUN_CONCURRENCY   default: 100
  CLOUD_RUN_MIN_INSTANCES default: 1 for production; 0 otherwise
  CLOUD_RUN_MAX_INSTANCES default: 3 for production; 1 otherwise
  CIRCLE_MEMBER_LIMIT     default: 6; snapshotted on newly created Circles (2-100)
  LIVE_COACH_SERVER_AUDIO_MODE default: dynamic for production; disabled otherwise
  LIVE_COACH_ACCESS_MODE       default: founding_trial for production; open_beta otherwise
  LIVE_COACH_CONFIG_VERSION    default: 2 for production; 1 otherwise
  LIVE_COACH_CATALOG_VERSION   default: 2026-09-01.1
  LIVE_COACH_ENABLED_LOCALES   default: en,zh-Hans
  LIVE_COACH_ENABLED_PERSONAS  default: supportive,focused product IDs
  LIVE_COACH_ENABLED_VOICE_PROFILES default: one female and one male product voice ID
  LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT default: 100 for production; 0 otherwise
  LIVE_COACH_FOUNDING_USER_LIMIT default: 1000
  LIVE_COACH_TRIAL_RUN_LIMIT      default: 3
  LIVE_COACH_CUE_VALIDITY_MILLISECONDS default: 5000
  LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS default: 1500
  LIVE_COACH_PLANNER_ENABLED  default: true for production; false otherwise
  GEMINI_LIVE_COACH_PLANNER_MODEL default: gemini-3.1-pro-preview
  GEMINI_VERTEX_PROJECT_ID    default: PROJECT_ID
  GEMINI_VERTEX_LOCATION      default: global
  GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS default: 20000
  LIVE_COACH_AUDIO_PACK_PUBLISHED default: true for production; false otherwise
  LIVE_COACH_AUDIO_MANIFEST_URL defaults to the approved production pack in production
  LIVE_COACH_AUDIO_ASSET_BASE_URL defaults to the approved production pack in production
  GOOGLE_CLOUD_TTS_ENABLED     default: true
  GOOGLE_CLOUD_TTS_API_ENDPOINT default: us-texttospeech.googleapis.com
  GOOGLE_CLOUD_TTS_ENDPOINT_KEY default: google-cloud-tts-us
  GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION default: us
  GOOGLE_CLOUD_TTS_MODEL       optional override; default: chirp3-hd
  GOOGLE_CLOUD_TTS_VOICE_MAP   optional override; default: approved female/male Chirp 3 HD map
  ALIBABA_AI_ENABLED           default: false
  AI_ROUTE_POLICY_VERSION      default: 2 for production; 1 otherwise
  ALIBABA_AI_ENDPOINT_KEY      default: alibaba-sg-ws-i638drcm5lthrc29
  ALIBABA_AI_DEPLOYMENT_REGION default: ap-southeast-1
  ALIBABA_AI_BASE_URL          default: approved Singapore workspace compatible-mode/v1 URL
  ALIBABA_LIVE_COACH_MODEL     optional override; default: qwen3-omni-flash-2025-12-01
  ALIBABA_TTS_BASE_URL         optional override; defaults to the workspace api/v1 URL
  ALIBABA_FIXED_AUDIO_MODEL    optional override; default: qwen3-tts-instruct-flash-2026-01-26
  ALIBABA_LIVE_COACH_VOICE_MAP optional legacy override; default: approved female/male locale map
  ALIBABA_AI_API_KEY_SECRET    used only when ALIBABA_AI_ENABLED=true
  SOURCE_DIR              default: backend
  GCLOUD_BIN              default: $HOME/google-cloud-sdk/bin/gcloud, then PATH
  NPM_BIN                 optional npm path
  NODE_BIN                optional node path for TypeScript fallback
  RUN_LOCAL_BUILD=0       skip local build before deploy
  RUN_HEALTH_CHECK=0      skip /health check after deploy
  HEALTH_CHECK_RETRIES    default: 5 retries after the first attempt
  HEALTH_CHECK_RETRY_DELAY_SECONDS default: 5
  ALLOW_DIRTY_BACKEND=1   allow deploy with uncommitted backend changes
  QUIET=0                 allow interactive gcloud prompts

Examples:
  ./scripts/deploy-backend-gcloud.sh
  RUN_LOCAL_BUILD=0 ./scripts/deploy-backend-gcloud.sh
  ./scripts/deploy-backend-gcloud.sh --revision-suffix=manual-test
USAGE
  exit 0
fi

PROJECT_ID="${PROJECT_ID:-outbound-494602}"
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-bruce.xia74@gmail.com}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-outbound-api}"
if [[ "$PROJECT_ID" == "outbound-494602" && "$SERVICE" == "outbound-api" ]]; then
  production_profile=1
else
  production_profile=0
fi
if [[ "$production_profile" == "1" ]]; then
  default_min_instances=1
  default_max_instances=3
  default_live_coach_mode=dynamic
  default_live_coach_access=founding_trial
  default_live_coach_config_version=2
  default_live_coach_rollout_percent=100
  default_live_coach_planner_enabled=true
  default_live_coach_pack_published=true
  default_live_coach_manifest_url="https://storage.googleapis.com/outbound-494602-live-coach-audio/live-coach/2026-09-01.1/manifest.json"
  default_live_coach_asset_base_url="https://storage.googleapis.com/outbound-494602-live-coach-audio/live-coach/2026-09-01.1/assets"
  default_ai_route_policy_version=2
else
  default_min_instances=0
  default_max_instances=1
  default_live_coach_mode=disabled
  default_live_coach_access=open_beta
  default_live_coach_config_version=1
  default_live_coach_rollout_percent=0
  default_live_coach_planner_enabled=false
  default_live_coach_pack_published=false
  default_live_coach_manifest_url=""
  default_live_coach_asset_base_url=""
  default_ai_route_policy_version=1
fi
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-outbound-api-runtime@$PROJECT_ID.iam.gserviceaccount.com}"
APPLE_CLIENT_ID="${APPLE_CLIENT_ID:-plainstride.outbound}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-WT54K7D7VH}"
APPLE_KEY_ID="${APPLE_KEY_ID:-8Z4P665DD3}"
AUTH_ACCESS_KEY_ID="${AUTH_ACCESS_KEY_ID:-production-v1}"
GOOGLE_AUTH_CLIENT_IDS="${GOOGLE_AUTH_CLIENT_IDS:-186140050970-8ft54ba43tqp5pvha14o1uu8tlvg274k.apps.googleusercontent.com,186140050970-9modifn0lqrpgvm62udhnjap2m1pk7cm.apps.googleusercontent.com}"
IOS_APP_STORE_URL="${IOS_APP_STORE_URL:-https://apps.apple.com/us/app/plainstride/id6800191455}"
CLOUD_SQL_INSTANCE="${CLOUD_SQL_INSTANCE:-$PROJECT_ID:$REGION:outbound-db}"
CLOUD_RUN_CONCURRENCY="${CLOUD_RUN_CONCURRENCY:-100}"
CLOUD_RUN_MIN_INSTANCES="${CLOUD_RUN_MIN_INSTANCES:-$default_min_instances}"
CLOUD_RUN_MAX_INSTANCES="${CLOUD_RUN_MAX_INSTANCES:-$default_max_instances}"
CIRCLE_MEMBER_LIMIT="${CIRCLE_MEMBER_LIMIT:-6}"
LIVE_COACH_SERVER_AUDIO_MODE="${LIVE_COACH_SERVER_AUDIO_MODE:-$default_live_coach_mode}"
LIVE_COACH_ACCESS_MODE="${LIVE_COACH_ACCESS_MODE:-$default_live_coach_access}"
LIVE_COACH_CONFIG_VERSION="${LIVE_COACH_CONFIG_VERSION:-$default_live_coach_config_version}"
LIVE_COACH_CATALOG_VERSION="${LIVE_COACH_CATALOG_VERSION:-2026-09-01.1}"
LIVE_COACH_ENABLED_LOCALES="${LIVE_COACH_ENABLED_LOCALES:-en,zh-Hans}"
LIVE_COACH_ENABLED_PERSONAS="${LIVE_COACH_ENABLED_PERSONAS:-plainstride_supportive_v1,plainstride_focused_v1}"
LIVE_COACH_ENABLED_VOICE_PROFILES="${LIVE_COACH_ENABLED_VOICE_PROFILES:-plainstride_warm_1,plainstride_clear_1}"
LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT="${LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT:-$default_live_coach_rollout_percent}"
LIVE_COACH_FOUNDING_USER_LIMIT="${LIVE_COACH_FOUNDING_USER_LIMIT:-1000}"
LIVE_COACH_TRIAL_RUN_LIMIT="${LIVE_COACH_TRIAL_RUN_LIMIT:-3}"
LIVE_COACH_CUE_VALIDITY_MILLISECONDS="${LIVE_COACH_CUE_VALIDITY_MILLISECONDS:-5000}"
LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS="${LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS:-1500}"
LIVE_COACH_PLANNER_ENABLED="${LIVE_COACH_PLANNER_ENABLED:-$default_live_coach_planner_enabled}"
GEMINI_LIVE_COACH_PLANNER_MODEL="${GEMINI_LIVE_COACH_PLANNER_MODEL:-gemini-3.1-pro-preview}"
GEMINI_VERTEX_PROJECT_ID="${GEMINI_VERTEX_PROJECT_ID:-$PROJECT_ID}"
GEMINI_VERTEX_LOCATION="${GEMINI_VERTEX_LOCATION:-global}"
GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS="${GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS:-20000}"
LIVE_COACH_AUDIO_PACK_PUBLISHED="${LIVE_COACH_AUDIO_PACK_PUBLISHED:-$default_live_coach_pack_published}"
LIVE_COACH_AUDIO_MANIFEST_URL="${LIVE_COACH_AUDIO_MANIFEST_URL:-$default_live_coach_manifest_url}"
LIVE_COACH_AUDIO_ASSET_BASE_URL="${LIVE_COACH_AUDIO_ASSET_BASE_URL:-$default_live_coach_asset_base_url}"
GOOGLE_CLOUD_TTS_ENABLED="${GOOGLE_CLOUD_TTS_ENABLED:-true}"
GOOGLE_CLOUD_TTS_API_ENDPOINT="${GOOGLE_CLOUD_TTS_API_ENDPOINT:-us-texttospeech.googleapis.com}"
GOOGLE_CLOUD_TTS_ENDPOINT_KEY="${GOOGLE_CLOUD_TTS_ENDPOINT_KEY:-google-cloud-tts-us}"
GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION="${GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION:-us}"
GOOGLE_CLOUD_TTS_MODEL="${GOOGLE_CLOUD_TTS_MODEL:-}"
GOOGLE_CLOUD_TTS_VOICE_MAP="${GOOGLE_CLOUD_TTS_VOICE_MAP:-}"
ALIBABA_AI_ENABLED="${ALIBABA_AI_ENABLED:-false}"
AI_ROUTE_POLICY_VERSION="${AI_ROUTE_POLICY_VERSION:-$default_ai_route_policy_version}"
ALIBABA_AI_ENDPOINT_KEY="${ALIBABA_AI_ENDPOINT_KEY:-alibaba-sg-ws-i638drcm5lthrc29}"
ALIBABA_AI_DEPLOYMENT_REGION="${ALIBABA_AI_DEPLOYMENT_REGION:-ap-southeast-1}"
ALIBABA_AI_BASE_URL="${ALIBABA_AI_BASE_URL:-https://ws-i638drcm5lthrc29.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1}"
ALIBABA_LIVE_COACH_MODEL="${ALIBABA_LIVE_COACH_MODEL:-}"
ALIBABA_TTS_BASE_URL="${ALIBABA_TTS_BASE_URL:-}"
ALIBABA_FIXED_AUDIO_MODEL="${ALIBABA_FIXED_AUDIO_MODEL:-}"
ALIBABA_LIVE_COACH_VOICE_MAP="${ALIBABA_LIVE_COACH_VOICE_MAP:-}"
ALIBABA_AI_API_KEY_SECRET="${ALIBABA_AI_API_KEY_SECRET:-outbound-alibaba-ai-api-key}"
SOURCE_DIR="${SOURCE_DIR:-backend}"
GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
NPM_BIN="${NPM_BIN:-}"
NODE_BIN="${NODE_BIN:-}"
RUN_LOCAL_BUILD="${RUN_LOCAL_BUILD:-1}"
RUN_HEALTH_CHECK="${RUN_HEALTH_CHECK:-1}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
HEALTH_CHECK_RETRY_DELAY_SECONDS="${HEALTH_CHECK_RETRY_DELAY_SECONDS:-5}"
ALLOW_DIRTY_BACKEND="${ALLOW_DIRTY_BACKEND:-0}"
QUIET="${QUIET:-1}"

if [[ ! -x "$GCLOUD_BIN" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  else
    echo "gcloud was not found. Set GCLOUD_BIN=/path/to/gcloud or install the Google Cloud SDK." >&2
    exit 1
  fi
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory '$SOURCE_DIR' does not exist." >&2
  exit 1
fi

if [[ "$ALLOW_DIRTY_BACKEND" != "1" ]] && [[ -n "$(git status --short -- "$SOURCE_DIR")" ]]; then
  echo "Backend has uncommitted changes. Commit them, or rerun with ALLOW_DIRTY_BACKEND=1." >&2
  git status --short -- "$SOURCE_DIR" >&2
  exit 1
fi

if [[ "$RUN_LOCAL_BUILD" != "0" ]]; then
  pushd "$SOURCE_DIR" >/dev/null
  if [[ -z "$NPM_BIN" ]] && command -v npm >/dev/null 2>&1; then
    NPM_BIN="$(command -v npm)"
  fi
  if [[ -n "$NPM_BIN" ]]; then
    if [[ ! -d node_modules ]]; then
      "$NPM_BIN" ci
    fi
    "$NPM_BIN" run build
  else
    if [[ -z "$NODE_BIN" ]] && command -v node >/dev/null 2>&1; then
      NODE_BIN="$(command -v node)"
    fi
    if [[ -z "$NODE_BIN" || ! -x node_modules/typescript/bin/tsc ]]; then
      echo "npm was not found, and the local TypeScript fallback is unavailable." >&2
      echo "Install dependencies with npm ci, set NPM_BIN, or rerun with RUN_LOCAL_BUILD=0." >&2
      exit 1
    fi
    "$NODE_BIN" node_modules/typescript/bin/tsc -p tsconfig.json
  fi
  popd >/dev/null
fi

secret_bindings=(
  "DATABASE_URL=outbound-database-url:latest"
  "APP_AI_KEY=outbound-app-ai-key:latest"
  "RESEND_API_KEY=outbound-resend-api-key:latest"
  "APPLE_PRIVATE_KEY=outbound-apple-private-key:latest"
  "AUTH_ACCESS_PRIVATE_KEY=outbound-auth-access-private-key:latest"
  "AUTH_ACCESS_PUBLIC_KEYS=outbound-auth-access-public-keys:latest"
)
if [[ "$ALIBABA_AI_ENABLED" == "true" && -n "$ALIBABA_AI_API_KEY_SECRET" ]]; then
  secret_bindings+=("ALIBABA_AI_API_KEY=$ALIBABA_AI_API_KEY_SECRET:latest")
fi
secret_vars="$(IFS=,; echo "${secret_bindings[*]}")"

environment_bindings=(
  "FEEDBACK_EMAIL_FROM=Plainstride <info@plainstride.com>"
  "APPLE_CLIENT_ID=$APPLE_CLIENT_ID"
  "APPLE_TEAM_ID=$APPLE_TEAM_ID"
  "APPLE_KEY_ID=$APPLE_KEY_ID"
  "AUTH_ACCESS_KEY_ID=$AUTH_ACCESS_KEY_ID"
  "GOOGLE_AUTH_CLIENT_IDS=$GOOGLE_AUTH_CLIENT_IDS"
  "AUTH_ACCEPT_LEGACY_FIREBASE=true"
  "IOS_APP_STORE_URL=$IOS_APP_STORE_URL"
  "CIRCLE_MEMBER_LIMIT=$CIRCLE_MEMBER_LIMIT"
  "LIVE_COACH_SERVER_AUDIO_MODE=$LIVE_COACH_SERVER_AUDIO_MODE"
  "LIVE_COACH_ACCESS_MODE=$LIVE_COACH_ACCESS_MODE"
  "LIVE_COACH_CONFIG_VERSION=$LIVE_COACH_CONFIG_VERSION"
  "LIVE_COACH_CATALOG_VERSION=$LIVE_COACH_CATALOG_VERSION"
  "LIVE_COACH_ENABLED_LOCALES=$LIVE_COACH_ENABLED_LOCALES"
  "LIVE_COACH_ENABLED_PERSONAS=$LIVE_COACH_ENABLED_PERSONAS"
  "LIVE_COACH_ENABLED_VOICE_PROFILES=$LIVE_COACH_ENABLED_VOICE_PROFILES"
  "LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT=$LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT"
  "LIVE_COACH_FOUNDING_USER_LIMIT=$LIVE_COACH_FOUNDING_USER_LIMIT"
  "LIVE_COACH_TRIAL_RUN_LIMIT=$LIVE_COACH_TRIAL_RUN_LIMIT"
  "LIVE_COACH_CUE_VALIDITY_MILLISECONDS=$LIVE_COACH_CUE_VALIDITY_MILLISECONDS"
  "LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS=$LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS"
  "LIVE_COACH_PLANNER_ENABLED=$LIVE_COACH_PLANNER_ENABLED"
  "GEMINI_LIVE_COACH_PLANNER_MODEL=$GEMINI_LIVE_COACH_PLANNER_MODEL"
  "GEMINI_VERTEX_PROJECT_ID=$GEMINI_VERTEX_PROJECT_ID"
  "GEMINI_VERTEX_LOCATION=$GEMINI_VERTEX_LOCATION"
  "GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS=$GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS"
  "LIVE_COACH_AUDIO_PACK_PUBLISHED=$LIVE_COACH_AUDIO_PACK_PUBLISHED"
  "GOOGLE_CLOUD_TTS_ENABLED=$GOOGLE_CLOUD_TTS_ENABLED"
  "GOOGLE_CLOUD_TTS_API_ENDPOINT=$GOOGLE_CLOUD_TTS_API_ENDPOINT"
  "GOOGLE_CLOUD_TTS_ENDPOINT_KEY=$GOOGLE_CLOUD_TTS_ENDPOINT_KEY"
  "GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION=$GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION"
  "ALIBABA_AI_ENABLED=$ALIBABA_AI_ENABLED"
  "AI_ROUTE_POLICY_VERSION=$AI_ROUTE_POLICY_VERSION"
  "ALIBABA_AI_ENDPOINT_KEY=$ALIBABA_AI_ENDPOINT_KEY"
  "ALIBABA_AI_DEPLOYMENT_REGION=$ALIBABA_AI_DEPLOYMENT_REGION"
)
if [[ -n "$LIVE_COACH_AUDIO_MANIFEST_URL" ]]; then
  environment_bindings+=("LIVE_COACH_AUDIO_MANIFEST_URL=$LIVE_COACH_AUDIO_MANIFEST_URL")
fi
if [[ -n "$LIVE_COACH_AUDIO_ASSET_BASE_URL" ]]; then
  environment_bindings+=("LIVE_COACH_AUDIO_ASSET_BASE_URL=$LIVE_COACH_AUDIO_ASSET_BASE_URL")
fi
if [[ -n "$GOOGLE_CLOUD_TTS_MODEL" ]]; then
  environment_bindings+=("GOOGLE_CLOUD_TTS_MODEL=$GOOGLE_CLOUD_TTS_MODEL")
fi
if [[ -n "$GOOGLE_CLOUD_TTS_VOICE_MAP" ]]; then
  environment_bindings+=("GOOGLE_CLOUD_TTS_VOICE_MAP=$GOOGLE_CLOUD_TTS_VOICE_MAP")
fi
if [[ -n "$ALIBABA_AI_BASE_URL" ]]; then
  environment_bindings+=("ALIBABA_AI_BASE_URL=$ALIBABA_AI_BASE_URL")
fi
if [[ -n "$ALIBABA_LIVE_COACH_MODEL" ]]; then
  environment_bindings+=("ALIBABA_LIVE_COACH_MODEL=$ALIBABA_LIVE_COACH_MODEL")
fi
if [[ -n "$ALIBABA_TTS_BASE_URL" ]]; then
  environment_bindings+=("ALIBABA_TTS_BASE_URL=$ALIBABA_TTS_BASE_URL")
fi
if [[ -n "$ALIBABA_FIXED_AUDIO_MODEL" ]]; then
  environment_bindings+=("ALIBABA_FIXED_AUDIO_MODEL=$ALIBABA_FIXED_AUDIO_MODEL")
fi
if [[ -n "$ALIBABA_LIVE_COACH_VOICE_MAP" ]]; then
  environment_bindings+=("ALIBABA_LIVE_COACH_VOICE_MAP=$ALIBABA_LIVE_COACH_VOICE_MAP")
fi
environment_vars="^|^$(IFS='|'; echo "${environment_bindings[*]}")"

deploy_args=(
  run deploy "$SERVICE"
  "--project=$PROJECT_ID"
  "--account=$GCLOUD_ACCOUNT"
  "--region=$REGION"
  "--source=$SOURCE_DIR"
  --allow-unauthenticated
  "--service-account=$RUNTIME_SERVICE_ACCOUNT"
  "--set-cloudsql-instances=$CLOUD_SQL_INSTANCE"
  "--network=default"
  "--subnet=default"
  "--vpc-egress=private-ranges-only"
  "--concurrency=$CLOUD_RUN_CONCURRENCY"
  "--min=$CLOUD_RUN_MIN_INSTANCES"
  "--max=$CLOUD_RUN_MAX_INSTANCES"
  "--max-instances=$CLOUD_RUN_MAX_INSTANCES"
  "--update-secrets=$secret_vars"
  "--update-env-vars=$environment_vars"
)

if [[ "$QUIET" == "1" ]]; then
  deploy_args+=(--quiet)
fi

echo "Deploying $SERVICE to Cloud Run project=$PROJECT_ID region=$REGION account=$GCLOUD_ACCOUNT"
"$GCLOUD_BIN" "${deploy_args[@]}" "$@"

deploy_without_traffic=0
for extra_arg in "$@"; do
  if [[ "$extra_arg" == "--no-traffic" ]]; then
    deploy_without_traffic=1
    break
  fi
done
if [[ "$deploy_without_traffic" == "0" ]]; then
  echo "Routing production traffic to the latest ready revision"
  "$GCLOUD_BIN" run services update-traffic "$SERVICE" \
    "--project=$PROJECT_ID" \
    "--region=$REGION" \
    --to-latest \
    --quiet
fi

service_url="$("$GCLOUD_BIN" run services describe "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  --format='value(status.url)')"

echo "Cloud Run URL: $service_url"

if [[ "$RUN_HEALTH_CHECK" != "0" ]]; then
  echo "Checking $service_url/health"
  curl --fail --silent --show-error \
    --retry "$HEALTH_CHECK_RETRIES" \
    --retry-all-errors \
    --retry-delay "$HEALTH_CHECK_RETRY_DELAY_SECONDS" \
    "$service_url/health"
  echo
fi
