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
  CLOUD_SQL_INSTANCE      default: PROJECT_ID:REGION:outbound-db
  CLOUD_RUN_CONCURRENCY   default: 100
  CLOUD_RUN_MIN_INSTANCES default: 0 (scale to zero before public release)
  CLOUD_RUN_MAX_INSTANCES default: 1
  LIVE_COACH_SERVER_AUDIO_MODE default: disabled
  LIVE_COACH_ACCESS_MODE       default: open_beta
  LIVE_COACH_CONFIG_VERSION    default: 1
  LIVE_COACH_CATALOG_VERSION   default: 2026-08-28.1
  LIVE_COACH_ENABLED_PERSONAS  default: supportive,focused product IDs
  LIVE_COACH_ENABLED_VOICE_PROFILES default: approved six product voice IDs
  LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT default: 0
  LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE default: 8
  LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME default: 15
  LIVE_COACH_CUE_VALIDITY_MILLISECONDS default: 5000
  LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS default: 4000
  LIVE_COACH_AUDIO_PACK_PUBLISHED default: false
  LIVE_COACH_AUDIO_MANIFEST_URL optional immutable HTTPS manifest URL
  LIVE_COACH_AUDIO_ASSET_BASE_URL optional immutable HTTPS asset base URL
  ALIBABA_AI_ENABLED           default: false
  AI_ROUTE_POLICY_VERSION      default: 1
  ALIBABA_AI_ENDPOINT_KEY      default: alibaba-global-primary
  ALIBABA_AI_DEPLOYMENT_REGION default: ap-southeast-1
  ALIBABA_AI_BASE_URL          provider workspace compatible-mode/v1 URL
  ALIBABA_LIVE_COACH_MODEL     optional override; default: qwen3-omni-flash-2025-12-01
  ALIBABA_LIVE_COACH_VOICE_MAP optional override; default: approved 3 female/3 male locale map
  ALIBABA_AI_API_KEY_SECRET    optional Secret Manager secret name to bind
  SOURCE_DIR              default: backend
  GCLOUD_BIN              default: $HOME/google-cloud-sdk/bin/gcloud, then PATH
  NPM_BIN                 optional npm path
  NODE_BIN                optional node path for TypeScript fallback
  RUN_LOCAL_BUILD=0       skip local build before deploy
  RUN_HEALTH_CHECK=0      skip /health check after deploy
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
RUNTIME_SERVICE_ACCOUNT="${RUNTIME_SERVICE_ACCOUNT:-outbound-api-runtime@$PROJECT_ID.iam.gserviceaccount.com}"
APPLE_CLIENT_ID="${APPLE_CLIENT_ID:-plainstride.outbound}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-WT54K7D7VH}"
APPLE_KEY_ID="${APPLE_KEY_ID:-8Z4P665DD3}"
AUTH_ACCESS_KEY_ID="${AUTH_ACCESS_KEY_ID:-production-v1}"
CLOUD_SQL_INSTANCE="${CLOUD_SQL_INSTANCE:-$PROJECT_ID:$REGION:outbound-db}"
CLOUD_RUN_CONCURRENCY="${CLOUD_RUN_CONCURRENCY:-100}"
CLOUD_RUN_MIN_INSTANCES="${CLOUD_RUN_MIN_INSTANCES:-0}"
CLOUD_RUN_MAX_INSTANCES="${CLOUD_RUN_MAX_INSTANCES:-1}"
LIVE_COACH_SERVER_AUDIO_MODE="${LIVE_COACH_SERVER_AUDIO_MODE:-disabled}"
LIVE_COACH_ACCESS_MODE="${LIVE_COACH_ACCESS_MODE:-open_beta}"
LIVE_COACH_CONFIG_VERSION="${LIVE_COACH_CONFIG_VERSION:-1}"
LIVE_COACH_CATALOG_VERSION="${LIVE_COACH_CATALOG_VERSION:-2026-08-28.1}"
LIVE_COACH_ENABLED_PERSONAS="${LIVE_COACH_ENABLED_PERSONAS:-plainstride_supportive_v1,plainstride_focused_v1}"
LIVE_COACH_ENABLED_VOICE_PROFILES="${LIVE_COACH_ENABLED_VOICE_PROFILES:-plainstride_warm_1,plainstride_gentle_1,plainstride_composed_1,plainstride_clear_1,plainstride_driven_1,plainstride_easygoing_1}"
LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT="${LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT:-0}"
LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE="${LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE:-8}"
LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME="${LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME:-15}"
LIVE_COACH_CUE_VALIDITY_MILLISECONDS="${LIVE_COACH_CUE_VALIDITY_MILLISECONDS:-5000}"
LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS="${LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS:-4000}"
LIVE_COACH_AUDIO_PACK_PUBLISHED="${LIVE_COACH_AUDIO_PACK_PUBLISHED:-false}"
LIVE_COACH_AUDIO_MANIFEST_URL="${LIVE_COACH_AUDIO_MANIFEST_URL:-}"
LIVE_COACH_AUDIO_ASSET_BASE_URL="${LIVE_COACH_AUDIO_ASSET_BASE_URL:-}"
ALIBABA_AI_ENABLED="${ALIBABA_AI_ENABLED:-false}"
AI_ROUTE_POLICY_VERSION="${AI_ROUTE_POLICY_VERSION:-1}"
ALIBABA_AI_ENDPOINT_KEY="${ALIBABA_AI_ENDPOINT_KEY:-alibaba-global-primary}"
ALIBABA_AI_DEPLOYMENT_REGION="${ALIBABA_AI_DEPLOYMENT_REGION:-ap-southeast-1}"
ALIBABA_AI_BASE_URL="${ALIBABA_AI_BASE_URL:-}"
ALIBABA_LIVE_COACH_MODEL="${ALIBABA_LIVE_COACH_MODEL:-}"
ALIBABA_LIVE_COACH_VOICE_MAP="${ALIBABA_LIVE_COACH_VOICE_MAP:-}"
ALIBABA_AI_API_KEY_SECRET="${ALIBABA_AI_API_KEY_SECRET:-}"
SOURCE_DIR="${SOURCE_DIR:-backend}"
GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
NPM_BIN="${NPM_BIN:-}"
NODE_BIN="${NODE_BIN:-}"
RUN_LOCAL_BUILD="${RUN_LOCAL_BUILD:-1}"
RUN_HEALTH_CHECK="${RUN_HEALTH_CHECK:-1}"
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
if [[ -n "$ALIBABA_AI_API_KEY_SECRET" ]]; then
  secret_bindings+=("ALIBABA_AI_API_KEY=$ALIBABA_AI_API_KEY_SECRET:latest")
fi
secret_vars="$(IFS=,; echo "${secret_bindings[*]}")"

environment_bindings=(
  "FEEDBACK_EMAIL_FROM=Plainstride <info@plainstride.com>"
  "APPLE_CLIENT_ID=$APPLE_CLIENT_ID"
  "APPLE_TEAM_ID=$APPLE_TEAM_ID"
  "APPLE_KEY_ID=$APPLE_KEY_ID"
  "AUTH_ACCESS_KEY_ID=$AUTH_ACCESS_KEY_ID"
  "AUTH_ACCEPT_LEGACY_FIREBASE=true"
  "LIVE_COACH_SERVER_AUDIO_MODE=$LIVE_COACH_SERVER_AUDIO_MODE"
  "LIVE_COACH_ACCESS_MODE=$LIVE_COACH_ACCESS_MODE"
  "LIVE_COACH_CONFIG_VERSION=$LIVE_COACH_CONFIG_VERSION"
  "LIVE_COACH_CATALOG_VERSION=$LIVE_COACH_CATALOG_VERSION"
  "LIVE_COACH_ENABLED_PERSONAS=$LIVE_COACH_ENABLED_PERSONAS"
  "LIVE_COACH_ENABLED_VOICE_PROFILES=$LIVE_COACH_ENABLED_VOICE_PROFILES"
  "LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT=$LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT"
  "LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE=$LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE"
  "LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME=$LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME"
  "LIVE_COACH_CUE_VALIDITY_MILLISECONDS=$LIVE_COACH_CUE_VALIDITY_MILLISECONDS"
  "LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS=$LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS"
  "LIVE_COACH_AUDIO_PACK_PUBLISHED=$LIVE_COACH_AUDIO_PACK_PUBLISHED"
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
if [[ -n "$ALIBABA_AI_BASE_URL" ]]; then
  environment_bindings+=("ALIBABA_AI_BASE_URL=$ALIBABA_AI_BASE_URL")
fi
if [[ -n "$ALIBABA_LIVE_COACH_MODEL" ]]; then
  environment_bindings+=("ALIBABA_LIVE_COACH_MODEL=$ALIBABA_LIVE_COACH_MODEL")
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

service_url="$("$GCLOUD_BIN" run services describe "$SERVICE" \
  "--project=$PROJECT_ID" \
  "--region=$REGION" \
  --format='value(status.url)')"

echo "Cloud Run URL: $service_url"

if [[ "$RUN_HEALTH_CHECK" != "0" ]]; then
  echo "Checking $service_url/health"
  curl --fail --silent --show-error "$service_url/health"
  echo
fi
