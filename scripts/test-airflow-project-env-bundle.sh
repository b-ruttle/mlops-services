#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

DAGS_ROOT="${TEST_ROOT}/dags"
PROJECTS_ROOT="${TEST_ROOT}/container-projects"
PROJECTS_HOST_ROOT="${TEST_ROOT}/host-projects"

mkdir -p "${DAGS_ROOT}" \
  "${PROJECTS_ROOT}/gnss/dags" \
  "${PROJECTS_ROOT}/my-project/dags" \
  "${PROJECTS_ROOT}/gnss/airflow" \
  "${PROJECTS_ROOT}/my-project/airflow"

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

AIRFLOW__CORE__DAGS_FOLDER="${DAGS_ROOT}" \
AIRFLOW_PROJECTS_ROOT="${PROJECTS_ROOT}" \
AIRFLOW_PROJECTS_HOST_ROOT="${PROJECTS_HOST_ROOT}" \
AIRFLOW_SHARED_DAGS_DIR="${PROJECTS_ROOT}/gnss/dags" \
  bash airflow/scripts/prepare-airflow-projects.sh

BUNDLE="${DAGS_ROOT}/.project-env/all-projects.env"
[[ -f "${BUNDLE}" ]]
[[ -L "${DAGS_ROOT}/gnss" ]]
[[ -L "${DAGS_ROOT}/my-project" ]]

set -a
# shellcheck source=/dev/null
source "${BUNDLE}"
set +a

[[ "${GNSS_RUNNER_IMAGE}" == "gnss-runner:test" ]]
[[ "${GNSS_REPO_HOST_DIR}" == "${PROJECTS_HOST_ROOT}/gnss" ]]
[[ "${MY_PROJECT_RUNNER_IMAGE}" == "my-project-runner:test" ]]
[[ "${MY_PROJECT_REPO_HOST_DIR}" == "${PROJECTS_HOST_ROOT}/my-project" ]]

echo "airflow project env bundle test passed"
