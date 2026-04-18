#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${ENV_DIR:-${ROOT_DIR}/env}"
MANIFEST_NAME="${AIRFLOW_PROJECT_MANIFEST_NAME:-.airflow-project.env}"

set -a
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

resolve_repo_dir_var "MLOPS_EXAMPLES_DIR" "${ROOT_DIR}/../mlops-examples"
resolve_repo_dir_var "AIRFLOW_PROJECTS_DIR" "${ROOT_DIR}/.."

print_header() {
  printf '%-20s %-48s %-48s\n' "PROJECT" "DAGS_DIR" "ENV_FILE"
  printf '%-20s %-48s %-48s\n' "-------" "--------" "--------"
}

list_projects() {
  local manifest_file
  local repo_dir
  local project_name
  local dags_dir
  local env_file

  print_header
  printf '%-20s %-48s %-48s\n' "mlops-examples" "${MLOPS_EXAMPLES_DIR}/dags" "-"

  while IFS= read -r manifest_file; do
    repo_dir="$(dirname "${manifest_file}")"
    unset PROJECT_NAME DAGS_DIR ENV_FILE
    # shellcheck source=/dev/null
    source "${manifest_file}"

    project_name="${PROJECT_NAME:-$(basename "${repo_dir}")}"
    dags_dir="${repo_dir}/${DAGS_DIR:-dags}"
    env_file="-"
    if [[ -n "${ENV_FILE:-}" ]]; then
      env_file="${repo_dir}/${ENV_FILE}"
    fi

    printf '%-20s %-48s %-48s\n' "${project_name}" "${dags_dir}" "${env_file}"
  done < <(find "${AIRFLOW_PROJECTS_DIR}" -mindepth 2 -maxdepth 2 -type f -name "${MANIFEST_NAME}" | sort)
}

validate_projects() {
  local manifest_file
  local repo_dir
  local project_name
  local dags_dir
  local env_file
  local had_error=0

  [[ -d "${AIRFLOW_PROJECTS_DIR}" ]] || {
    echo "ERROR: AIRFLOW_PROJECTS_DIR does not exist: ${AIRFLOW_PROJECTS_DIR}" >&2
    return 1
  }

  [[ -d "${MLOPS_EXAMPLES_DIR}/dags" ]] || {
    echo "ERROR: shared DAG directory is missing: ${MLOPS_EXAMPLES_DIR}/dags" >&2
    return 1
  }

  while IFS= read -r manifest_file; do
    repo_dir="$(dirname "${manifest_file}")"
    unset PROJECT_NAME DAGS_DIR ENV_FILE
    # shellcheck source=/dev/null
    source "${manifest_file}"

    project_name="${PROJECT_NAME:-$(basename "${repo_dir}")}"
    dags_dir="${repo_dir}/${DAGS_DIR:-dags}"
    env_file=""
    if [[ -n "${ENV_FILE:-}" ]]; then
      env_file="${repo_dir}/${ENV_FILE}"
    fi

    if [[ ! -d "${dags_dir}" ]]; then
      echo "ERROR: DAG directory for ${project_name} is missing: ${dags_dir}" >&2
      had_error=1
    fi

    if [[ -n "${ENV_FILE:-}" && ! -f "${env_file}" ]]; then
      echo "ERROR: env file for ${project_name} is missing: ${env_file}" >&2
      had_error=1
    fi
  done < <(find "${AIRFLOW_PROJECTS_DIR}" -mindepth 2 -maxdepth 2 -type f -name "${MANIFEST_NAME}" | sort)

  [[ "${had_error}" -eq 0 ]]
}

usage() {
  cat <<'EOF'
Usage: ./scripts/airflow-projects.sh <command>

Commands:
  list      Show discoverable Airflow projects under AIRFLOW_PROJECTS_DIR
  validate  Validate project-owned Airflow manifests
EOF
}

case "${1:-list}" in
  list)
    list_projects
    ;;
  validate)
    validate_projects
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
