#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

FAKE_BIN="${TEST_ROOT}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/airflow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "db" && "${2:-}" == "migrate" ]]; then
  exit 0
fi

if [[ "${1:-}" == "users" ]]; then
  found_password=0
  for arg in "$@"; do
    [[ "${arg}" == "--password=-leading-hyphen-password" ]] && found_password=1
  done
  if [[ "${found_password}" -ne 1 ]]; then
    echo "ERROR: Airflow password was not passed as a single --password=value argument" >&2
    exit 2
  fi

  if [[ "${2:-}" == "create" && "${FAKE_AIRFLOW_CREATE_RESULT:-success}" == "fail" ]]; then
    exit 1
  fi
  if [[ "${2:-}" == "create" || "${2:-}" == "reset-password" ]]; then
    exit 0
  fi
fi

echo "ERROR: unexpected fake Airflow invocation: $*" >&2
exit 2
EOF
chmod +x "${FAKE_BIN}/airflow"

PATH="${FAKE_BIN}:${PATH}" \
AIRFLOW_ADMIN_USERNAME="airflow-admin" \
AIRFLOW_ADMIN_PASSWORD="-leading-hyphen-password" \
AIRFLOW_ADMIN_FIRSTNAME="Airflow" \
AIRFLOW_ADMIN_LASTNAME="Admin" \
AIRFLOW_ADMIN_EMAIL="airflow-admin@example.local" \
  bash airflow/scripts/init-airflow.sh

PATH="${FAKE_BIN}:${PATH}" \
FAKE_AIRFLOW_CREATE_RESULT="fail" \
AIRFLOW_ADMIN_USERNAME="airflow-admin" \
AIRFLOW_ADMIN_PASSWORD="-leading-hyphen-password" \
AIRFLOW_ADMIN_FIRSTNAME="Airflow" \
AIRFLOW_ADMIN_LASTNAME="Admin" \
AIRFLOW_ADMIN_EMAIL="airflow-admin@example.local" \
  bash airflow/scripts/init-airflow.sh

echo "airflow init argument test passed"
