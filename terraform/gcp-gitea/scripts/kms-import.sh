#!/usr/bin/env bash
set -euo pipefail

# Import existing KMS keys into Terraform state without destroying resources.
# Usage:
#   PROJECT_ID=your-proj REGION=us-central1 ENV=prod ./scripts/kms-import.sh

PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-}
ENV=${ENV:-}

if [[ -z "$PROJECT_ID" || -z "$REGION" || -z "$ENV" ]]; then
  echo "Usage: PROJECT_ID=... REGION=... ENV=... $0" >&2
  exit 1
fi

PREFIX="${PROJECT_ID}-${ENV}"
KEYRING="${PREFIX}-keyring"
DISK_KEY="${PREFIX}-disk-key"
STORAGE_KEY="${PREFIX}-storage-key"
SECRETS_KEY="${PREFIX}-secrets-key"

echo "Importing KMS keys in projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING}"

maybe_import() {
  local addr="$1"; shift
  local id="$1"; shift
  if terraform state list | grep -q "^${addr}$"; then
    echo "State already contains ${addr} — skipping import"
  else
    echo "Importing ${addr} -> ${id}"
    terraform import "${addr}" "${id}"
  fi
}

maybe_import 'google_kms_crypto_key.storage_key[0]' \
  "projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING}/cryptoKeys/${STORAGE_KEY}"

maybe_import 'google_kms_crypto_key.secrets_key[0]' \
  "projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING}/cryptoKeys/${SECRETS_KEY}"

echo "Done. Next: terraform plan -out=tfplan && terraform apply -auto-approve tfplan"

