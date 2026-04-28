#!/usr/bin/env bash
set -euo pipefail

DAGS_ROOT="${AIRFLOW__CORE__DAGS_FOLDER:-/opt/airflow/dags}"
PROJECTS_ROOT="${AIRFLOW_PROJECTS_ROOT:-/opt/airflow/projects-root}"
PROJECTS_HOST_ROOT="${AIRFLOW_PROJECTS_HOST_ROOT:-}"
SHARED_DAGS_DIR="${AIRFLOW_SHARED_DAGS_DIR:-/opt/mlops-examples/dags}"
MANIFEST_NAME="${AIRFLOW_PROJECT_MANIFEST_NAME:-.airflow-project.env}"
PROJECT_ENV_BUNDLE="${DAGS_ROOT}/.project-env/all-projects.env"

sanitize_name() {
  local value="$1"
  value="${value//[^a-zA-Z0-9._-]/-}"
  value="${value##-}"
  value="${value%%-}"
  printf '%s\n' "${value}"
}

env_var_project_name() {
  local value="$1"
  value="${value^^}"
  value="${value//[^A-Z0-9_]/_}"
  while [[ "${value}" == _* ]]; do
    value="${value#_}"
  done
  while [[ "${value}" == *_ ]]; do
    value="${value%_}"
  done
  if [[ "${value}" =~ ^[0-9] ]]; then
    value="_${value}"
  fi
  printf '%s\n' "${value}"
}

register_dag_source() {
  local name="$1"
  local source_dir="$2"
  local sanitized_name

  if [[ ! -d "${source_dir}" ]]; then
    echo "ERROR: DAG source for project '${name}' is missing: ${source_dir}" >&2
    exit 1
  fi

  sanitized_name="$(sanitize_name "${name}")"
  if [[ -z "${sanitized_name}" ]]; then
    echo "ERROR: project name '${name}' does not produce a usable DAG directory name." >&2
    exit 1
  fi

  ln -sfn "${source_dir}" "${DAGS_ROOT}/${sanitized_name}"
}

prepare_dags_root() {
  mkdir -p "${DAGS_ROOT}"
  find "${DAGS_ROOT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

prepare_project_env_root() {
  mkdir -p "$(dirname "${PROJECT_ENV_BUNDLE}")"
  : > "${PROJECT_ENV_BUNDLE}"
}

append_env_file() {
  local env_file="$1"

  if [[ -f "${env_file}" ]]; then
    cat "${env_file}" >> "${PROJECT_ENV_BUNDLE}"
    printf '\n' >> "${PROJECT_ENV_BUNDLE}"
  fi
}

append_project_repo_host_dir() {
  local project_name="$1"
  local project_dir="$2"
  local env_project_name
  local env_var_name
  local repo_host_dir

  env_project_name="$(env_var_project_name "${project_name}")"
  if [[ -z "${env_project_name}" ]]; then
    echo "ERROR: project name '${project_name}' does not produce a usable env var prefix." >&2
    exit 1
  fi

  env_var_name="${env_project_name}_REPO_HOST_DIR"
  if [[ -n "${PROJECTS_HOST_ROOT}" && "${project_dir}" == "${PROJECTS_ROOT}"/* ]]; then
    repo_host_dir="${PROJECTS_HOST_ROOT%/}/${project_dir#"${PROJECTS_ROOT}/"}"
  else
    repo_host_dir="${project_dir}"
  fi

  printf 'export %s=%q\n' "${env_var_name}" "${repo_host_dir}" >> "${PROJECT_ENV_BUNDLE}"
}

prepare_registered_projects() {
  local manifest_file
  local project_dir
  local project_name
  local dags_dir
  local env_file

  if [[ ! -d "${PROJECTS_ROOT}" ]]; then
    return
  fi

  while IFS= read -r -d '' manifest_file; do
    project_dir="$(dirname "${manifest_file}")"
    unset PROJECT_NAME DAGS_DIR ENV_FILE
    # shellcheck source=/dev/null
    source "${manifest_file}"

    project_name="${PROJECT_NAME:-$(basename "${project_dir}")}"
    dags_dir="${project_dir}/${DAGS_DIR:-dags}"
    env_file=""
    if [[ -n "${ENV_FILE:-}" ]]; then
      env_file="${project_dir}/${ENV_FILE}"
    fi

    register_dag_source "${project_name}" "${dags_dir}"
    append_env_file "${env_file}"
    append_project_repo_host_dir "${project_name}" "${project_dir}"
  done < <(find "${PROJECTS_ROOT}" -mindepth 2 -maxdepth 2 -type f -name "${MANIFEST_NAME}" -print0 | sort -z)
}

prepare_dags_root
prepare_project_env_root
register_dag_source "mlops-examples" "${SHARED_DAGS_DIR}"
prepare_registered_projects
