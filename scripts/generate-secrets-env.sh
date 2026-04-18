#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_PATH="${ROOT_DIR}/env/secrets.env"
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-secrets-env.sh [--output PATH] [--force]

Generate a secrets env file for the local MLOps services stack.

Options:
  -o, --output PATH  Write to a custom output path.
  -f, --force        Overwrite the output file if it already exists.
  -h, --help         Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: missing value for $1" >&2
        exit 1
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${OUTPUT_PATH}" != /* ]]; then
  OUTPUT_PATH="${ROOT_DIR}/${OUTPUT_PATH}"
fi

if [[ -e "${OUTPUT_PATH}" && "${FORCE}" -ne 1 ]]; then
  echo "ERROR: ${OUTPUT_PATH} already exists. Re-run with --force to overwrite it." >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
TMP_FILE="$(mktemp)"
trap 'rm -f "${TMP_FILE}"' EXIT

python3 - <<'PY' > "${TMP_FILE}"
import base64
import os
import secrets


def pw(nbytes=24):
    return secrets.token_urlsafe(nbytes)


def key_hex(nbytes=32):
    return secrets.token_hex(nbytes)


def fernet_key():
    return base64.urlsafe_b64encode(os.urandom(32)).decode()


print("# --- Postgres ---")
print("POSTGRES_USER=postgres-admin")
print(f"POSTGRES_PASSWORD={pw(24)}")
print()

print("# --- RustFS (S3-compatible) ---")
print("RUSTFS_ACCESS_KEY=rustfs-admin")
print(f"RUSTFS_SECRET_KEY={pw(32)}")
print()

print("# --- MLflow basic auth bootstrap ---")
print(f"MLFLOW_FLASK_SERVER_SECRET_KEY={key_hex(32)}")
print("MLFLOW_AUTH_ADMIN_USERNAME=mlflow-admin")
print(f"MLFLOW_AUTH_ADMIN_PASSWORD={pw(24)}")
print()

print("# --- MLflow admin app login (separate from MLflow users) ---")
print("MLFLOW_ADMIN_APP_USERNAME=admin-app")
print(f"MLFLOW_ADMIN_APP_PASSWORD={pw(24)}")
print(f"MLFLOW_ADMIN_APP_SECRET_KEY={key_hex(32)}")
print()

print("# --- Airflow bootstrap ---")
print(f"AIRFLOW_FERNET_KEY={fernet_key()}")
print(f"AIRFLOW_SECRET_KEY={key_hex(32)}")
print("AIRFLOW_ADMIN_USERNAME=airflow-admin")
print(f"AIRFLOW_ADMIN_PASSWORD={pw(24)}")
print("AIRFLOW_ADMIN_FIRSTNAME=Airflow")
print("AIRFLOW_ADMIN_LASTNAME=Admin")
print("AIRFLOW_ADMIN_EMAIL=airflow-admin@example.local")
PY

mv "${TMP_FILE}" "${OUTPUT_PATH}"
trap - EXIT

echo "Wrote ${OUTPUT_PATH}"
