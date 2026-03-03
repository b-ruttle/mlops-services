# MLOps Services

Production-oriented MLOps service stack with:
- MLflow tracking server
- Postgres backend store
- RustFS artifact store
- Nginx reverse proxy (public entrypoint)
- oauth2-proxy (OIDC auth gateway)
- Keycloak (identity + group-based RBAC management)
- Vault (KV secrets source for runtime env materialization)

## Architecture

Public ingress:
- `nginx` exposes `80/443`
- `https://<PUBLIC_FQDN>/mlflow` for MLflow (authenticated)
- `https://<PUBLIC_FQDN>/oauth2/*` for oauth2-proxy callbacks
- `https://<PUBLIC_FQDN>/auth/*` for Keycloak

Internal-only services (Docker network `mlops`):
- `mlflow`
- `postgres`
- `rustfs`
- `keycloak-postgres`
- `oauth2-proxy`
- `keycloak`
- `vault` (bound to localhost by default)

## RBAC model

Access is enforced at Nginx using the `groups` OIDC claim:
- `mlops-viewer`: read-only (`GET`, `HEAD`, `OPTIONS`)
- `mlops-editor`: read + write (`POST`, `PUT`, `PATCH`, `DELETE`)
- `mlops-admin`: same API rights as editor; role assignment done in Keycloak admin UI

Keycloak realm bootstrap creates:
- realm `mlops`
- client `mlflow-gateway` (confidential client)
- groups `mlops-admin`, `mlops-editor`, `mlops-viewer`

## Environment loading

`scripts/compose.sh` loads env in this order:
1. `env/versions.env`
2. `env/config.env`
3. `.runtime/secrets.env` (if present, preferred)
4. `env/secrets.env` (fallback for local/dev)

`env/secrets.env` is gitignored. Start from `env/secrets.env.example`.

## Vault secrets flow (Phase 1)

KV paths:
- `secret/mlops-services/prod/postgres`
- `secret/mlops-services/prod/rustfs`
- `secret/mlops-services/prod/keycloak`
- `secret/mlops-services/prod/oauth2-proxy`
- `secret/mlops-services/prod/mlflow`

Helper scripts:
- `make vault-seed`: starts Vault, writes dev seed secrets + deploy policy, renders runtime secrets
- `make vault-render`: re-renders `.runtime/secrets.env` from Vault KV

Current implementation note:
- Vault runs in dev mode (`vault server -dev`) to simplify bootstrap in this repo.
- For true production, replace this with a persistent, sealed/unsealed Vault deployment pattern.

## TLS certificates

Nginx expects certificates mounted from `TLS_CERTS_DIR` (default `./nginx/certs`) with:
- `${TLS_CERT_FILE}` default `tls.crt`
- `${TLS_KEY_FILE}` default `tls.key`

Use company-managed certs for production.

## Quickstart

1. Copy and edit secrets:

```bash
cp env/secrets.env.example env/secrets.env
```

2. Seed Vault and render runtime secrets:

```bash
make vault-seed
```

3. Start services:

```bash
make up
```

4. Check status/logs:

```bash
make ps
make logs
```

## Make targets

- `make up`: start services (build if needed)
- `make down`: stop services
- `make ps`: show service status
- `make logs`: tail logs for all services
- `make logs SERVICE=mlflow`: tail logs for one service
- `make test`: smoke test (internal MLflow path by default)
- `make vault-seed`: seed local Vault KV + deploy policy
- `make vault-render`: render `.runtime/secrets.env` from Vault

## Smoke testing

Default smoke test validates MLflow functionality internally:

```bash
make test
```

Optional gateway check (expects unauthenticated redirect/deny):

```bash
SMOKE_CHECK_GATEWAY=true make test
```

## Troubleshooting

- Missing cert files: Nginx fails to start if `tls.crt`/`tls.key` are missing.
- Missing secrets: verify `.runtime/secrets.env` or `env/secrets.env` contains required keys.
- OIDC login loops: confirm `PUBLIC_FQDN`, Keycloak client secret, and callback URL alignment.
- Access denied for valid users: verify group membership in Keycloak (`mlops-viewer`, `mlops-editor`, `mlops-admin`).
