#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

DAGS_ROOT="${TEST_ROOT}/dags"
PLATFORM_DAGS_ROOT="${TEST_ROOT}/platform-dags"
PROJECTS_ROOT="${TEST_ROOT}/container-projects"
PROJECTS_HOST_ROOT="${TEST_ROOT}/host-projects"

mkdir -p "${DAGS_ROOT}" \
  "${PLATFORM_DAGS_ROOT}" \
  "${PROJECTS_ROOT}/gnss/dags" \
  "${PROJECTS_ROOT}/my-project/dags" \
  "${PROJECTS_ROOT}/mlops/repos/mlops-examples/dags" \
  "${PROJECTS_ROOT}/mlops/volumes/ignored-project/dags" \
  "${PROJECTS_ROOT}/gnss/airflow" \
  "${PROJECTS_ROOT}/my-project/airflow"

touch "${PLATFORM_DAGS_ROOT}/smoke.py"

cat > "${PROJECTS_ROOT}/gnss/.airflow-project.env" <<'EOF'
PROJECT_NAME=gnss
DAGS_DIR=dags
ENV_FILE=airflow/runtime.env
EOF

cat > "${PROJECTS_ROOT}/gnss/airflow/runtime.env" <<'EOF'
GNSS_RUNNER_IMAGE=gnss-runner:test
GNSS_REPO_HOST_DIR=/stale/manual/path
EOF

cat > "${PROJECTS_ROOT}/my-project/.airflow-project.env" <<'EOF'
PROJECT_NAME=my-project
DAGS_DIR=dags
ENV_FILE=airflow/runtime.env
EOF

cat > "${PROJECTS_ROOT}/my-project/airflow/runtime.env" <<'EOF'
MY_PROJECT_RUNNER_IMAGE=my-project-runner:test
EOF

cat > "${PROJECTS_ROOT}/mlops/repos/mlops-examples/.airflow-project.env" <<'EOF'
PROJECT_NAME=mlops-examples
DAGS_DIR=dags
EOF

cat > "${PROJECTS_ROOT}/mlops/volumes/ignored-project/.airflow-project.env" <<'EOF'
PROJECT_NAME=must-not-be-discovered
DAGS_DIR=dags
EOF

AIRFLOW__CORE__DAGS_FOLDER="${DAGS_ROOT}" \
AIRFLOW_PLATFORM_DAGS_DIR="${PLATFORM_DAGS_ROOT}" \
AIRFLOW_PROJECTS_ROOT="${PROJECTS_ROOT}" \
AIRFLOW_PROJECTS_HOST_ROOT="${PROJECTS_HOST_ROOT}" \
  bash airflow/scripts/prepare-airflow-projects.sh

BUNDLE="${DAGS_ROOT}/.project-env/all-projects.env"
[[ -f "${BUNDLE}" ]]
[[ -L "${DAGS_ROOT}/mlops-services" ]]
[[ -L "${DAGS_ROOT}/gnss" ]]
[[ -L "${DAGS_ROOT}/my-project" ]]
[[ -L "${DAGS_ROOT}/mlops-examples" ]]
[[ ! -e "${DAGS_ROOT}/must-not-be-discovered" ]]

set -a
# shellcheck source=/dev/null
source "${BUNDLE}"
set +a

[[ "${GNSS_RUNNER_IMAGE}" == "gnss-runner:test" ]]
[[ "${GNSS_REPO_HOST_DIR}" == "${PROJECTS_HOST_ROOT}/gnss" ]]
[[ "${MY_PROJECT_RUNNER_IMAGE}" == "my-project-runner:test" ]]
[[ "${MY_PROJECT_REPO_HOST_DIR}" == "${PROJECTS_HOST_ROOT}/my-project" ]]
[[ "${MLOPS_EXAMPLES_REPO_HOST_DIR}" == "${PROJECTS_HOST_ROOT}/mlops/repos/mlops-examples" ]]

# A standalone platform with no external project manifests must also prepare cleanly.
EMPTY_DAGS_ROOT="${TEST_ROOT}/empty-dags"
EMPTY_PROJECTS_ROOT="${TEST_ROOT}/empty-projects"
mkdir -p "${EMPTY_DAGS_ROOT}" "${EMPTY_PROJECTS_ROOT}"

AIRFLOW__CORE__DAGS_FOLDER="${EMPTY_DAGS_ROOT}" \
AIRFLOW_PLATFORM_DAGS_DIR="${PLATFORM_DAGS_ROOT}" \
AIRFLOW_PROJECTS_ROOT="${EMPTY_PROJECTS_ROOT}" \
AIRFLOW_PROJECTS_HOST_ROOT="${PROJECTS_HOST_ROOT}" \
  bash airflow/scripts/prepare-airflow-projects.sh

[[ -L "${EMPTY_DAGS_ROOT}/mlops-services" ]]
[[ -f "${EMPTY_DAGS_ROOT}/.project-env/all-projects.env" ]]
[[ ! -s "${EMPTY_DAGS_ROOT}/.project-env/all-projects.env" ]]

# Duplicate normalized project names must fail instead of overwriting a DAG link.
DUPLICATE_DAGS_ROOT="${TEST_ROOT}/duplicate-dags"
DUPLICATE_PROJECTS_ROOT="${TEST_ROOT}/duplicate-projects"
mkdir -p "${DUPLICATE_DAGS_ROOT}" \
  "${DUPLICATE_PROJECTS_ROOT}/first/dags" \
  "${DUPLICATE_PROJECTS_ROOT}/nested/second/dags"

cat > "${DUPLICATE_PROJECTS_ROOT}/first/.airflow-project.env" <<'EOF'
PROJECT_NAME=duplicate
EOF

cat > "${DUPLICATE_PROJECTS_ROOT}/nested/second/.airflow-project.env" <<'EOF'
PROJECT_NAME=duplicate
EOF

if AIRFLOW__CORE__DAGS_FOLDER="${DUPLICATE_DAGS_ROOT}" \
  AIRFLOW_PLATFORM_DAGS_DIR="${PLATFORM_DAGS_ROOT}" \
  AIRFLOW_PROJECTS_ROOT="${DUPLICATE_PROJECTS_ROOT}" \
  AIRFLOW_PROJECTS_HOST_ROOT="${PROJECTS_HOST_ROOT}" \
    bash airflow/scripts/prepare-airflow-projects.sh >/dev/null 2>&1; then
  echo "ERROR: duplicate Airflow project names unexpectedly passed validation" >&2
  exit 1
fi

echo "airflow project env bundle test passed"
