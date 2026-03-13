#!/bin/sh
set -eu

postgres_host="${POSTGRES_HOST:-postgres}"
postgres_port="${POSTGRES_PORT:-5432}"

create_db_if_missing() {
  db_name="$1"
  label="$2"

  if [ "$db_name" = "$POSTGRES_DB" ]; then
    echo "$label DB matches POSTGRES_DB; skipping extra DB creation."
    return 0
  fi

  psql \
    -v ON_ERROR_STOP=1 \
    --host "$postgres_host" \
    --port "$postgres_port" \
    --username "$POSTGRES_USER" \
    --dbname postgres <<EOSQL
SELECT format('CREATE DATABASE %I OWNER %I', '${db_name}', '${POSTGRES_USER}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec
EOSQL
}

auth_db="${MLFLOW_AUTH_POSTGRES_DB:-mlflow_auth}"
feast_db="${FEAST_POSTGRES_DB:-feast}"

if [ "$auth_db" = "$feast_db" ]; then
  echo "MLFLOW_AUTH_POSTGRES_DB and FEAST_POSTGRES_DB must be different."
  exit 1
fi

create_db_if_missing "$auth_db" "MLflow auth"
create_db_if_missing "$feast_db" "Feast"
