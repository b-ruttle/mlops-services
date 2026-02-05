#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${ENV_DIR:-${ROOT_DIR}/env}"

set -a
# Load env files in a fixed order so later files can override earlier values.
source "${ENV_DIR}/versions.env"
source "${ENV_DIR}/config.env"
source "${ENV_DIR}/secrets.env"
set +a

cd "${ROOT_DIR}"
exec docker compose "$@"
