#!/usr/bin/env bash
set -euo pipefail

/scripts/prepare-airflow-projects.sh

PROJECT_ENV_BUNDLE="${AIRFLOW__CORE__DAGS_FOLDER:-/opt/airflow/dags}/.project-env/all-projects.env"
if [[ -f "${PROJECT_ENV_BUNDLE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "${PROJECT_ENV_BUNDLE}"
  set +a
fi

if [[ $# -gt 0 && -f "$1" && ! -x "$1" ]]; then
  exec /bin/bash "$@"
fi

exec "$@"
