#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-outbound-494602}"
GOOGLE_CLOUD_TTS_API_ENDPOINT="${GOOGLE_CLOUD_TTS_API_ENDPOINT:-us-texttospeech.googleapis.com}"
export GOOGLE_CLOUD_TTS_API_ENDPOINT
export GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-$PROJECT_ID}"
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

if [[ ! "$GOOGLE_CLOUD_TTS_API_ENDPOINT" =~ ^[a-z0-9.-]+\.googleapis\.com$ ]]; then
  echo "GOOGLE_CLOUD_TTS_API_ENDPOINT must be a googleapis.com host name." >&2
  exit 1
fi

export GOOGLE_CLOUD_TTS_ENABLED=true
export ALIBABA_AI_ENABLED=false
cd "$ROOT_DIR/backend"
if [[ "$SMOKE" == "1" ]]; then
  npm run live-coach:generate-audio -- \
    --catalog-version 2026-08-30.1 \
    --provider google_cloud_tts \
    --voice-profile plainstride_warm_1 \
    --locale en \
    --cue voice.preview \
    --output .local/live-coach-smoke \
    "$@"
  exit 0
fi
if [[ " $* " == *" --voice-profile "* ]]; then
  npm run live-coach:generate-audio -- --catalog-version 2026-08-30.1 --provider google_cloud_tts "$@"
  exit 0
fi

for voice_profile in plainstride_warm_1 plainstride_clear_1; do
  npm run live-coach:generate-audio -- \
    --catalog-version 2026-08-30.1 \
    --provider google_cloud_tts \
    --voice-profile "$voice_profile" \
    "$@"
done
