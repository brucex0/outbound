#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage:
  APPLE_PRIVATE_KEY_FILE=/secure/path/AuthKey.p8 ./scripts/provision-production-auth.sh
  CONFIGURE_ONLY=1 ./scripts/provision-production-auth.sh

The full mode generates a new ES256 Plainstride access-token key pair in a
temporary directory, creates the three production Secret Manager secrets,
grants the Cloud Run runtime identity access, configures Cloud Run, deploys,
and checks /health.

CONFIGURE_ONLY=1 skips key generation, secret creation, and IAM grants. Use it
when the three secrets and their IAM bindings already exist.

Environment overrides:
  PROJECT_ID                 default: outbound-494602
  GCLOUD_ACCOUNT             default: bruce.xia74@gmail.com
  REGION                     default: us-central1
  SERVICE                    default: outbound-api
  RUNTIME_SERVICE_ACCOUNT    default: outbound-api-runtime@PROJECT_ID.iam.gserviceaccount.com
  APPLE_CLIENT_ID            default: plainstride.outbound
  APPLE_TEAM_ID              default: WT54K7D7VH
  APPLE_KEY_ID               default: 8Z4P665DD3
  AUTH_ACCESS_KEY_ID         default: production-v1
  APPLE_PRIVATE_KEY_FILE     required in full mode; path to Apple's .p8 file
  GCLOUD_BIN                 default: $HOME/google-cloud-sdk/bin/gcloud, then PATH
  CONFIGURE_ONLY             default: 0
  KEEP_GENERATED_KEYS        default: 0; retain generated access keys locally
  GENERATED_KEY_DIR          required when KEEP_GENERATED_KEYS=1

The script refuses to replace existing secrets. Rotate production keys through
a separate, explicit procedure so active and previous public keys overlap.
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
APPLE_PRIVATE_KEY_FILE="${APPLE_PRIVATE_KEY_FILE:-}"
GCLOUD_BIN="${GCLOUD_BIN:-$HOME/google-cloud-sdk/bin/gcloud}"
CONFIGURE_ONLY="${CONFIGURE_ONLY:-0}"
KEEP_GENERATED_KEYS="${KEEP_GENERATED_KEYS:-0}"
GENERATED_KEY_DIR="${GENERATED_KEY_DIR:-}"

if [[ ! -x "$GCLOUD_BIN" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GCLOUD_BIN="$(command -v gcloud)"
  else
    echo "gcloud was not found. Set GCLOUD_BIN=/path/to/gcloud." >&2
    exit 1
  fi
fi

if [[ "$CONFIGURE_ONLY" != "1" ]]; then
  for command_name in openssl jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "$command_name is required for full provisioning." >&2
      exit 1
    fi
  done
  if [[ -z "$APPLE_PRIVATE_KEY_FILE" || ! -f "$APPLE_PRIVATE_KEY_FILE" ]]; then
    echo "Set APPLE_PRIVATE_KEY_FILE to the downloaded Apple .p8 key." >&2
    exit 1
  fi

  key_dir="$(mktemp -d "${TMPDIR:-/tmp}/outbound-production-auth.XXXXXX")"
  cleanup() {
    if [[ "$KEEP_GENERATED_KEYS" == "1" ]]; then
      if [[ -z "$GENERATED_KEY_DIR" || "$GENERATED_KEY_DIR" != /* ]]; then
        echo "GENERATED_KEY_DIR must be an absolute path when KEEP_GENERATED_KEYS=1." >&2
        exit 1
      fi
      mkdir -p "$GENERATED_KEY_DIR"
      chmod 700 "$GENERATED_KEY_DIR"
      cp "$key_dir/access-private.pem" "$key_dir/access-public.pem" "$key_dir/access-public-keys.json" "$GENERATED_KEY_DIR/"
      chmod 600 \
        "$GENERATED_KEY_DIR/access-private.pem" \
        "$GENERATED_KEY_DIR/access-public.pem" \
        "$GENERATED_KEY_DIR/access-public-keys.json"
      echo "Generated access keys retained in $GENERATED_KEY_DIR"
    fi
    expected_temp_root="${TMPDIR:-/tmp}"
    case "$key_dir" in
      "$expected_temp_root"/outbound-production-auth.*) ;;
      *) echo "Refusing to remove unexpected temporary path: $key_dir" >&2; return 1 ;;
    esac
    if [[ ! -d "$key_dir" || -L "$key_dir" ]]; then
      echo "Refusing to remove invalid temporary directory: $key_dir" >&2
      return 1
    fi
    rm -rf -- "$key_dir"
  }
  trap cleanup EXIT

  openssl ecparam -name prime256v1 -genkey -noout -out "$key_dir/access-private.pem"
  openssl ec -in "$key_dir/access-private.pem" -pubout -out "$key_dir/access-public.pem"
  jq -Rs --arg kid "$AUTH_ACCESS_KEY_ID" '{($kid): .}' "$key_dir/access-public.pem" > "$key_dir/access-public-keys.json"
  chmod 600 "$key_dir"/*

  secret_names=(
    outbound-apple-private-key
    outbound-auth-access-private-key
    outbound-auth-access-public-keys
  )
  secret_files=(
    "$APPLE_PRIVATE_KEY_FILE"
    "$key_dir/access-private.pem"
    "$key_dir/access-public-keys.json"
  )

  for secret_name in "${secret_names[@]}"; do
    if "$GCLOUD_BIN" secrets describe "$secret_name" --project="$PROJECT_ID" >/dev/null 2>&1; then
      echo "Secret $secret_name already exists; refusing to replace any authentication secrets." >&2
      exit 1
    fi
  done

  for index in "${!secret_names[@]}"; do
    secret_name="${secret_names[$index]}"
    secret_file="${secret_files[$index]}"
    "$GCLOUD_BIN" secrets create "$secret_name" \
      --project="$PROJECT_ID" \
      --replication-policy=automatic \
      --data-file="$secret_file"
    "$GCLOUD_BIN" secrets add-iam-policy-binding "$secret_name" \
      --project="$PROJECT_ID" \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role=roles/secretmanager.secretAccessor
  done
fi

for secret_name in outbound-apple-private-key outbound-auth-access-private-key outbound-auth-access-public-keys; do
  "$GCLOUD_BIN" secrets versions list "$secret_name" \
    --project="$PROJECT_ID" \
    --filter='state=ENABLED' \
    --limit=1 \
    --format='value(name)' | grep -q . || {
      echo "Secret $secret_name has no enabled version." >&2
      exit 1
    }
done

"$GCLOUD_BIN" run services update "$SERVICE" \
  --project="$PROJECT_ID" \
  --account="$GCLOUD_ACCOUNT" \
  --region="$REGION" \
  --update-secrets="APPLE_PRIVATE_KEY=outbound-apple-private-key:latest,AUTH_ACCESS_PRIVATE_KEY=outbound-auth-access-private-key:latest,AUTH_ACCESS_PUBLIC_KEYS=outbound-auth-access-public-keys:latest" \
  --update-env-vars="APPLE_CLIENT_ID=$APPLE_CLIENT_ID,APPLE_TEAM_ID=$APPLE_TEAM_ID,APPLE_KEY_ID=$APPLE_KEY_ID,AUTH_ACCESS_KEY_ID=$AUTH_ACCESS_KEY_ID,AUTH_ACCEPT_LEGACY_FIREBASE=true" \
  --quiet

PROJECT_ID="$PROJECT_ID" \
GCLOUD_ACCOUNT="$GCLOUD_ACCOUNT" \
REGION="$REGION" \
SERVICE="$SERVICE" \
RUNTIME_SERVICE_ACCOUNT="$RUNTIME_SERVICE_ACCOUNT" \
APPLE_CLIENT_ID="$APPLE_CLIENT_ID" \
APPLE_TEAM_ID="$APPLE_TEAM_ID" \
APPLE_KEY_ID="$APPLE_KEY_ID" \
AUTH_ACCESS_KEY_ID="$AUTH_ACCESS_KEY_ID" \
GCLOUD_BIN="$GCLOUD_BIN" \
  ./scripts/deploy-backend-gcloud.sh
