#!/usr/bin/env bash
set -euo pipefail

MANIFEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="../backend/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create backend/.env with the production values first." >&2
  exit 1
fi

kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

# Values are piped directly to kubectl and are not written into a YAML file.
# This imports the backend environment file into a Kubernetes Secret.
kubectl create secret generic cheapkart-backend-secrets \
  --namespace cheapkart \
  --from-env-file="${ENV_FILE}" \
  --dry-run=client \
  --output yaml | kubectl apply -f -
