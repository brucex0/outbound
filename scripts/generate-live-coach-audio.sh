#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--list" ]]; then
  cd "$ROOT_DIR/backend"
  npm run live-coach:list-audio
  exit 0
fi

if [[ -z "${ALIBABA_AI_API_KEY:-}" && -n "${DASHSCOPE_API_KEY:-}" ]]; then
  export ALIBABA_AI_API_KEY="$DASHSCOPE_API_KEY"
fi
if [[ -z "${ALIBABA_AI_API_KEY:-}" ]]; then
  echo "Set ALIBABA_AI_API_KEY or DASHSCOPE_API_KEY before generating audio." >&2
  exit 1
fi
if [[ -z "${ALIBABA_AI_BASE_URL:-}" ]]; then
  echo "Set ALIBABA_AI_BASE_URL to the workspace-specific Singapore compatible-mode/v1 URL." >&2
  exit 1
fi
if [[ ! "$ALIBABA_AI_BASE_URL" =~ ^https://[^/]+\.ap-southeast-1\.maas\.aliyuncs\.com/compatible-mode/v1/?$ ]]; then
  echo "ALIBABA_AI_BASE_URL must be the HTTPS workspace-specific Singapore compatible-mode/v1 URL." >&2
  exit 1
fi

export ALIBABA_AI_ENABLED=true
cd "$ROOT_DIR/backend"
npm run live-coach:generate-audio -- --catalog-version 2026-08-28.1 --provider alibaba "$@"
