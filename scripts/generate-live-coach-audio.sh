#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-outbound-494602}"
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-bruce.xia74@gmail.com}"
ALIBABA_AI_API_KEY_SECRET="${ALIBABA_AI_API_KEY_SECRET:-outbound-alibaba-ai-api-key}"
ALIBABA_AI_BASE_URL="${ALIBABA_AI_BASE_URL:-https://ws-i638drcm5lthrc29.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1}"
ALIBABA_TTS_BASE_URL="${ALIBABA_TTS_BASE_URL:-https://ws-i638drcm5lthrc29.ap-southeast-1.maas.aliyuncs.com/api/v1}"
export ALIBABA_AI_BASE_URL
export ALIBABA_TTS_BASE_URL
SMOKE=0

if [[ "${1:-}" == "--list" ]]; then
  cd "$ROOT_DIR/backend"
  npm run live-coach:list-audio
  exit 0
fi

if [[ "${1:-}" == "--smoke" ]]; then
  SMOKE=1
  shift
fi

if [[ -z "${ALIBABA_AI_API_KEY:-}" && -n "${DASHSCOPE_API_KEY:-}" ]]; then
  export ALIBABA_AI_API_KEY="$DASHSCOPE_API_KEY"
fi
if [[ -z "${ALIBABA_AI_API_KEY:-}" ]]; then
  GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
  if [[ ! -x "$GCLOUD_BIN" ]] && command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  fi
  if [[ -x "$GCLOUD_BIN" ]]; then
    if alibaba_key="$("$GCLOUD_BIN" secrets versions access latest \
      --secret="$ALIBABA_AI_API_KEY_SECRET" \
      --project="$PROJECT_ID" \
      --account="$GCLOUD_ACCOUNT" 2>/dev/null)"; then
      export ALIBABA_AI_API_KEY="$alibaba_key"
      unset alibaba_key
    fi
  fi
fi
if [[ -z "${ALIBABA_AI_API_KEY:-}" ]]; then
  echo "Alibaba API key unavailable. Set ALIBABA_AI_API_KEY/DASHSCOPE_API_KEY or create Secret Manager secret '$ALIBABA_AI_API_KEY_SECRET'." >&2
  exit 1
fi
if [[ ! "$ALIBABA_AI_BASE_URL" =~ ^https://[^/]+\.ap-southeast-1\.maas\.aliyuncs\.com/compatible-mode/v1/?$ ]]; then
  echo "ALIBABA_AI_BASE_URL must be the HTTPS workspace-specific Singapore compatible-mode/v1 URL." >&2
  exit 1
fi
if [[ ! "$ALIBABA_TTS_BASE_URL" =~ ^https://[^/]+\.ap-southeast-1\.maas\.aliyuncs\.com/api/v1/?$ ]]; then
  echo "ALIBABA_TTS_BASE_URL must be the HTTPS workspace-specific Singapore api/v1 URL." >&2
  exit 1
fi

export ALIBABA_AI_ENABLED=true
cd "$ROOT_DIR/backend"
if [[ "$SMOKE" == "1" ]]; then
  npm run live-coach:generate-audio -- \
    --catalog-version 2026-08-30.1 \
    --provider alibaba \
    --voice-profile plainstride_warm_1 \
    --locale en \
    --cue voice.preview \
    --output .local/live-coach-smoke \
    "$@"
  exit 0
fi
npm run live-coach:generate-audio -- --catalog-version 2026-08-30.1 --provider alibaba "$@"
