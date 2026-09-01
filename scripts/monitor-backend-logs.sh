#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: ./scripts/monitor-backend-logs.sh [tail|recent|errors|recent-errors|local] [gcloud flags]

Monitors Plainstride backend logs. The default mode is "tail".

Modes:
  tail           Stream production Cloud Run logs until interrupted.
  recent         Read recent production Cloud Run logs once.
  errors         Stream production logs with severity ERROR or higher.
  recent-errors  Read recent production errors once.
  local          Follow the backend log created by the iOS build helper.

Environment overrides:
  PROJECT_ID      default: outbound-494602
  GCLOUD_ACCOUNT  default: bruce.xia74@gmail.com
  REGION          default: us-central1
  SERVICE         default: outbound-api
  GCLOUD_BIN      default: $HOME/google-cloud-sdk/bin/gcloud, then PATH
  LOG_FRESHNESS   default: 1h (recent modes only)
  LOG_LIMIT       default: 200 (recent modes only)
  LOCAL_LOG_FILE  default: ${TMPDIR:-/tmp}/plainstride-local-backend.log

Examples:
  ./scripts/monitor-backend-logs.sh
  ./scripts/monitor-backend-logs.sh recent
  ./scripts/monitor-backend-logs.sh errors
  ./scripts/monitor-backend-logs.sh tail --log-filter='textPayload:"[live-coach]"'
  LOG_FRESHNESS=6h LOG_LIMIT=500 ./scripts/monitor-backend-logs.sh recent
  ./scripts/monitor-backend-logs.sh local
USAGE
  exit 0
fi

mode="${1:-tail}"
if [[ $# -gt 0 ]]; then
  shift
fi

PROJECT_ID="${PROJECT_ID:-outbound-494602}"
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-bruce.xia74@gmail.com}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-outbound-api}"
GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
LOG_FRESHNESS="${LOG_FRESHNESS:-1h}"
LOG_LIMIT="${LOG_LIMIT:-200}"
LOCAL_LOG_FILE="${LOCAL_LOG_FILE:-${TMPDIR:-/tmp}/plainstride-local-backend.log}"

if [[ "$mode" == "local" ]]; then
  if [[ $# -ne 0 ]]; then
    echo "The local mode does not accept gcloud flags." >&2
    exit 2
  fi
  if [[ ! -f "$LOCAL_LOG_FILE" ]]; then
    echo "Local backend log not found: $LOCAL_LOG_FILE" >&2
    echo "Start the local backend through scripts/build-install-bruce-main.sh, or set LOCAL_LOG_FILE." >&2
    exit 1
  fi
  exec tail -f "$LOCAL_LOG_FILE"
fi

if [[ ! -x "$GCLOUD_BIN" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  else
    echo "gcloud was not found. Set GCLOUD_BIN=/path/to/gcloud or install the Google Cloud SDK." >&2
    exit 1
  fi
fi

common_flags=(
  "--project=$PROJECT_ID"
  "--account=$GCLOUD_ACCOUNT"
  "--region=$REGION"
)

case "$mode" in
  tail)
    exec "$GCLOUD_BIN" beta run services logs tail "$SERVICE" "${common_flags[@]}" "$@"
    ;;
  recent)
    exec "$GCLOUD_BIN" run services logs read "$SERVICE" "${common_flags[@]}" \
      "--freshness=$LOG_FRESHNESS" "--limit=$LOG_LIMIT" "$@"
    ;;
  errors)
    exec "$GCLOUD_BIN" beta run services logs tail "$SERVICE" "${common_flags[@]}" \
      '--log-filter=severity>=ERROR' "$@"
    ;;
  recent-errors)
    exec "$GCLOUD_BIN" run services logs read "$SERVICE" "${common_flags[@]}" \
      "--freshness=$LOG_FRESHNESS" "--limit=$LOG_LIMIT" \
      '--log-filter=severity>=ERROR' "$@"
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    echo "Run ./scripts/monitor-backend-logs.sh --help for usage." >&2
    exit 2
    ;;
esac
