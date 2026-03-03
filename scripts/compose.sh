#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${ENV_DIR:-${ROOT_DIR}/env}"
RUNTIME_SECRETS_FILE="${ROOT_DIR}/.runtime/secrets.env"

set -a
# Load env files in a fixed order so later files can override earlier values.
source "${ENV_DIR}/versions.env"
source "${ENV_DIR}/config.env"
if [[ -f "${RUNTIME_SECRETS_FILE}" ]]; then
  # Production path: secrets materialized from Vault KV.
  source "${RUNTIME_SECRETS_FILE}"
else
  # Development fallback: local file copied from secrets.env.example.
  source "${ENV_DIR}/secrets.env"
fi
set +a

cd "${ROOT_DIR}"
exec docker compose "$@"
