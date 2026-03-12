#!/bin/sh
set -eu

auth_db="${MLFLOW_AUTH_POSTGRES_DB:-mlflow_auth}"

if [ "$auth_db" = "$POSTGRES_DB" ]; then
  echo "MLFLOW_AUTH_POSTGRES_DB matches POSTGRES_DB; skipping extra auth DB creation."
  exit 0
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<EOF
SELECT format('CREATE DATABASE %I OWNER %I', '${auth_db}', '${POSTGRES_USER}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${auth_db}')\gexec
EOF
