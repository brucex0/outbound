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

deploy_args=(
  run deploy "$SERVICE"
  "--project=$PROJECT_ID"
  "--account=$GCLOUD_ACCOUNT"
  "--region=$REGION"
  "--source=$SOURCE_DIR"
  --allow-unauthenticated
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
