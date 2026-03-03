#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE="${ROOT_DIR}/scripts/compose.sh"
ENV_DIR="${ENV_DIR:-${ROOT_DIR}/env}"
POLICY_FILE="${SCRIPT_DIR}/mlops-services-deploy-policy.hcl"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command '$1' is not installed." >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq

set -a
source "${ENV_DIR}/versions.env"
source "${ENV_DIR}/config.env"
source "${ENV_DIR}/secrets.env"
set +a

VAULT_ADDR="${VAULT_ADDR:-http://${VAULT_PORT_BIND}:${VAULT_PORT}}"
VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_DEV_ROOT_TOKEN}}"

echo "Starting Vault service..."
"${COMPOSE}" up -d vault >/dev/null

echo "Waiting for Vault API at ${VAULT_ADDR}..."
for _ in {1..60}; do
  if curl -fsS "${VAULT_ADDR}/v1/sys/health" >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -fsS "${VAULT_ADDR}/v1/sys/health" >/dev/null; then
  echo "ERROR: Vault API did not become ready." >&2
  exit 1
fi

mount_resp_file="$(mktemp)"
trap 'rm -f "${mount_resp_file}"' EXIT

mount_status="$(curl -s -o "${mount_resp_file}" -w "%{http_code}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/sys/mounts/${VAULT_KV_MOUNT}")"

if [[ "${mount_status}" == "404" ]]; then
  echo "Enabling KV v2 mount '${VAULT_KV_MOUNT}'..."
  curl -fsS \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{"type":"kv","options":{"version":"2"}}' \
    "${VAULT_ADDR}/v1/sys/mounts/${VAULT_KV_MOUNT}" >/dev/null
elif [[ "${mount_status}" == "200" ]]; then
  mount_version="$(jq -r '.data.options.version // "1"' <"${mount_resp_file}")"
  if [[ "${mount_version}" != "2" ]]; then
    echo "ERROR: ${VAULT_KV_MOUNT} exists but is not KV v2." >&2
    exit 1
  fi
else
  echo "ERROR: failed to inspect Vault mount '${VAULT_KV_MOUNT}' (HTTP ${mount_status})." >&2
  exit 1
fi

write_secret() {
  local path="$1"
  local payload="$2"
  curl -fsS \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${payload}" \
    "${VAULT_ADDR}/v1/${VAULT_KV_MOUNT}/data/${VAULT_SECRET_PREFIX}/${path}" >/dev/null
}

echo "Writing seed secrets..."
write_secret "postgres" "$(jq -n \
  --arg postgres_user "${POSTGRES_USER}" \
  --arg postgres_password "${POSTGRES_PASSWORD}" \
  '{data:{POSTGRES_USER:$postgres_user,POSTGRES_PASSWORD:$postgres_password}}')"

write_secret "rustfs" "$(jq -n \
  --arg access_key "${RUSTFS_ACCESS_KEY}" \
  --arg secret_key "${RUSTFS_SECRET_KEY}" \
  '{data:{RUSTFS_ACCESS_KEY:$access_key,RUSTFS_SECRET_KEY:$secret_key}}')"

write_secret "keycloak" "$(jq -n \
  --arg admin_user "${KEYCLOAK_ADMIN_USER}" \
  --arg admin_password "${KEYCLOAK_ADMIN_PASSWORD}" \
  --arg db_user "${KEYCLOAK_DB_USER}" \
  --arg db_password "${KEYCLOAK_DB_PASSWORD}" \
  --arg gateway_secret "${KEYCLOAK_GATEWAY_CLIENT_SECRET}" \
  '{data:{KEYCLOAK_ADMIN_USER:$admin_user,KEYCLOAK_ADMIN_PASSWORD:$admin_password,KEYCLOAK_DB_USER:$db_user,KEYCLOAK_DB_PASSWORD:$db_password,KEYCLOAK_GATEWAY_CLIENT_SECRET:$gateway_secret}}')"

write_secret "oauth2-proxy" "$(jq -n \
  --arg client_secret "${OAUTH2_PROXY_CLIENT_SECRET}" \
  --arg cookie_secret "${OAUTH2_PROXY_COOKIE_SECRET}" \
  '{data:{OAUTH2_PROXY_CLIENT_SECRET:$client_secret,OAUTH2_PROXY_COOKIE_SECRET:$cookie_secret}}')"

write_secret "mlflow" "$(jq -n \
  --arg tracking_uri "https://${PUBLIC_FQDN}${MLFLOW_BASE_PATH}" \
  --arg artifact_bucket "${MLFLOW_ARTIFACT_BUCKET}" \
  '{data:{MLFLOW_TRACKING_URI:$tracking_uri,MLFLOW_ARTIFACT_BUCKET:$artifact_bucket}}')"

policy_payload="$(jq -n --rawfile policy "${POLICY_FILE}" '{policy: $policy}')"

echo "Writing deploy policy: mlops-services-deploy"
curl -fsS \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -X PUT \
  -d "${policy_payload}" \
  "${VAULT_ADDR}/v1/sys/policies/acl/mlops-services-deploy" >/dev/null

echo "Rendering runtime secrets from Vault..."
"${SCRIPT_DIR}/render-secrets.sh"

echo "Vault seed complete."
