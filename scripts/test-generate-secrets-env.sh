#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

for iteration in $(seq 1 25); do
  output_path="${TEST_ROOT}/secrets-${iteration}.env"
  ./scripts/generate-secrets-env.sh --output "${output_path}" >/dev/null

  unset POSTGRES_PASSWORD RUSTFS_SECRET_KEY MLFLOW_AUTH_ADMIN_PASSWORD
  unset MLFLOW_ADMIN_APP_PASSWORD AIRFLOW_FERNET_KEY AIRFLOW_ADMIN_PASSWORD
  # shellcheck source=/dev/null
  source "${output_path}"

  for var_name in \
    POSTGRES_PASSWORD \
    RUSTFS_SECRET_KEY \
    MLFLOW_AUTH_ADMIN_PASSWORD \
    MLFLOW_ADMIN_APP_PASSWORD \
    AIRFLOW_FERNET_KEY \
    AIRFLOW_ADMIN_PASSWORD; do
    value="${!var_name}"
    if [[ ! "${value:0:1}" =~ [[:alnum:]] ]]; then
      echo "ERROR: ${var_name} does not begin with an alphanumeric character" >&2
      exit 1
    fi
  done
done

echo "secret generation safety test passed"
