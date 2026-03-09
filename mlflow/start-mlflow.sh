#!/usr/bin/env bash
set -euo pipefail

: "${MLFLOW_FLASK_SERVER_SECRET_KEY:?MLFLOW_FLASK_SERVER_SECRET_KEY must be set}"
: "${MLFLOW_AUTH_ADMIN_PASSWORD:?MLFLOW_AUTH_ADMIN_PASSWORD must be set}"

MLFLOW_AUTH_ADMIN_USERNAME="${MLFLOW_AUTH_ADMIN_USERNAME:-admin}"
MLFLOW_AUTH_DEFAULT_PERMISSION="${MLFLOW_AUTH_DEFAULT_PERMISSION:-READ}"
MLFLOW_AUTH_CONFIG_PATH="${MLFLOW_AUTH_CONFIG_PATH:-/tmp/mlflow-basic-auth.ini}"
MLFLOW_AUTH_DATABASE_URI="${MLFLOW_AUTH_DATABASE_URI:-sqlite:////mlflow/auth/basic_auth.db}"
MLFLOW_BACKEND_STORE_URI="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:${POSTGRES_PORT}/${POSTGRES_DB}"

cat > "${MLFLOW_AUTH_CONFIG_PATH}" <<EOF2
[mlflow]
default_permission = ${MLFLOW_AUTH_DEFAULT_PERMISSION}
database_uri = ${MLFLOW_AUTH_DATABASE_URI}
admin_username = ${MLFLOW_AUTH_ADMIN_USERNAME}
admin_password = ${MLFLOW_AUTH_ADMIN_PASSWORD}
EOF2

# Apply auth DB migrations once before gunicorn workers boot.
python -m mlflow.server.auth db upgrade --url "${MLFLOW_AUTH_DATABASE_URI}"

export MLFLOW_AUTH_CONFIG_PATH

exec mlflow server \
  --host "${MLFLOW_BIND_HOST}" \
  --port "${MLFLOW_PORT}" \
  --backend-store-uri "${MLFLOW_BACKEND_STORE_URI}" \
  --artifacts-destination "s3://${MLFLOW_ARTIFACT_BUCKET}" \
  --serve-artifacts \
  --app-name basic-auth
