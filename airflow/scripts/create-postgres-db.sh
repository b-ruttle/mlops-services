#!/bin/sh
set -eu

postgres_host="${POSTGRES_HOST:-postgres}"
postgres_port="${POSTGRES_PORT:-5432}"
airflow_db="${AIRFLOW_POSTGRES_DB:-airflow}"

if [ "$airflow_db" = "$POSTGRES_DB" ]; then
  echo "Airflow DB matches POSTGRES_DB; skipping extra DB creation."
  exit 0
fi

psql \
  -v ON_ERROR_STOP=1 \
  --host "$postgres_host" \
  --port "$postgres_port" \
  --username "$POSTGRES_USER" \
  --dbname postgres <<EOSQL
SELECT format('CREATE DATABASE %I OWNER %I', '${airflow_db}', '${POSTGRES_USER}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${airflow_db}')\gexec
EOSQL
