#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_FILE="/opt/keycloak/bootstrap/realm-template.json"
IMPORT_DIR="/opt/keycloak/data/import"
REALM_FILE="${IMPORT_DIR}/mlops-realm.json"

mkdir -p "${IMPORT_DIR}"

sed \
  -e "s|__PUBLIC_FQDN__|${PUBLIC_FQDN}|g" \
  -e "s|__OAUTH2_PROXY_CLIENT_ID__|${OAUTH2_PROXY_CLIENT_ID}|g" \
  -e "s|__KEYCLOAK_GATEWAY_CLIENT_SECRET__|${KEYCLOAK_GATEWAY_CLIENT_SECRET}|g" \
  "${TEMPLATE_FILE}" > "${REALM_FILE}"

exec /opt/keycloak/bin/kc.sh start \
  --http-enabled=true \
  --http-port="${KEYCLOAK_PORT}" \
  --hostname="${PUBLIC_FQDN}" \
  --hostname-strict=false \
  --proxy-headers=xforwarded \
  --http-relative-path=/auth \
  --import-realm
