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

resolve_repo_dir_var() {
  local var_name="$1"
  local fallback_path="$2"
  local value="${!var_name:-}"

  if [[ -z "${value}" ]]; then
    if [[ -d "${fallback_path}" ]]; then
      value="${fallback_path}"
    else
      return
    fi
  elif [[ "${value}" != /* ]]; then
    value="${ROOT_DIR}/${value}"
  fi

  value="$(cd "${value}" && pwd)"
  printf -v "${var_name}" '%s' "${value}"
  export "${var_name}"
}

normalize_base_path_var() {
  local var_name="$1"
  local default_value="$2"
  local value="${!var_name:-${default_value}}"

  # Accept both "mlflow" and "/mlflow" for convenience.
  if [[ "${value}" != /* ]]; then
    value="/${value}"
  fi
  # Keep a stable no-trailing-slash form for generated URLs and nginx paths.
  value="${value%/}"
  if [[ -z "${value}" ]]; then
    echo "ERROR: ${var_name} must not be empty or '/'."
    exit 1
  fi

  printf -v "${var_name}" '%s' "${value}"
  export "${var_name}"
}

normalize_base_path_var "MLFLOW_BASE_PATH" "mlflow"
normalize_base_path_var "RUSTFS_BASE_PATH" "rustfs"

normalize_existing_base_path_vars() {
  local var_name
  for var_name in $(compgen -v); do
    [[ "${var_name}" == *_BASE_PATH ]] || continue
    [[ "${var_name}" == "MLFLOW_BASE_PATH" ]] && continue
    [[ "${var_name}" == "RUSTFS_BASE_PATH" ]] && continue
    # Normalize only variables that are already defined by env files.
    [[ -n "${!var_name+x}" ]] || continue
    normalize_base_path_var "${var_name}" "${!var_name}"
  done
}

normalize_existing_base_path_vars

resolve_repo_dir_var "MLOPS_EXAMPLES_DIR" "${ROOT_DIR}/../mlops-examples"

cd "${ROOT_DIR}"
exec docker compose "$@"
