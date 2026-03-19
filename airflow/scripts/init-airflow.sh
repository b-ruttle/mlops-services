#!/usr/bin/env bash
set -euo pipefail

airflow db migrate

if airflow users create \
  --role Admin \
  --username "${AIRFLOW_ADMIN_USERNAME}" \
  --password "${AIRFLOW_ADMIN_PASSWORD}" \
  --firstname "${AIRFLOW_ADMIN_FIRSTNAME}" \
  --lastname "${AIRFLOW_ADMIN_LASTNAME}" \
  --email "${AIRFLOW_ADMIN_EMAIL}"; then
  echo "Created Airflow admin user ${AIRFLOW_ADMIN_USERNAME}."
else
  echo "Airflow admin user ${AIRFLOW_ADMIN_USERNAME} already exists; resetting password."
  airflow users reset-password \
    --username "${AIRFLOW_ADMIN_USERNAME}" \
    --password "${AIRFLOW_ADMIN_PASSWORD}"
fi
