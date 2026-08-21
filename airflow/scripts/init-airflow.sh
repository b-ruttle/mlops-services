#!/usr/bin/env bash
set -euo pipefail

airflow db migrate

if airflow users create \
  --role Admin \
  --username "${AIRFLOW_ADMIN_USERNAME}" \
  --password="${AIRFLOW_ADMIN_PASSWORD}" \
  --firstname "${AIRFLOW_ADMIN_FIRSTNAME}" \
  --lastname "${AIRFLOW_ADMIN_LASTNAME}" \
  --email "${AIRFLOW_ADMIN_EMAIL}"; then
  echo "Created Airflow admin user ${AIRFLOW_ADMIN_USERNAME}."
else
  echo "Could not create Airflow admin user ${AIRFLOW_ADMIN_USERNAME}; trying a password reset in case it already exists."
  if airflow users reset-password \
    --username "${AIRFLOW_ADMIN_USERNAME}" \
    --password="${AIRFLOW_ADMIN_PASSWORD}"; then
    echo "Reset password for existing Airflow admin user ${AIRFLOW_ADMIN_USERNAME}."
  else
    echo "ERROR: failed to create or update Airflow admin user ${AIRFLOW_ADMIN_USERNAME}." >&2
    exit 1
  fi
fi
