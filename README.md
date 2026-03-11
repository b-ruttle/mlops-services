# MLOps Services

Local MLOps services for development and testing, orchestrated with Docker Compose.

The stack includes:
- MLflow (tracking server)
- Postgres (MLflow backend store & offline feature store)
- RustFS (S3-compatible object store)
- Nginx (single HTTP entrypoint with path-based routing)

## Quickstart

1. Configure secrets:
```bash
cp env/secrets.env.example env/secrets.env
# then edit env/secrets.env
```
Set strong values for:
- `MLFLOW_FLASK_SERVER_SECRET_KEY`
- `MLFLOW_AUTH_ADMIN_PASSWORD`

2. Start the stack:
```bash
make up
```

3. Open services (no hosts-file edits required by default):
- `http://localhost/mlflow`
- `http://localhost/rustfs` (RustFS console)
- `http://localhost/` (simple index page)

Stop services:
```bash
make down
```

## MLflow Users and Permissions

MLflow runs with built-in basic auth enabled so team members can use unique accounts and you can attribute runs to individual users.

- Bootstrap admin credentials come from `env/secrets.env`:
  - `MLFLOW_AUTH_ADMIN_USERNAME` (default `admin`)
  - `MLFLOW_AUTH_ADMIN_PASSWORD`
- `MLFLOW_FLASK_SERVER_SECRET_KEY` is required for MLflow session security.
- `MLFLOW_AUTH_DEFAULT_PERMISSION` (in `env/config.env`) sets the default permission for newly created users.

Recommended team workflow:
1. Keep one admin account for platform maintenance.
2. Create one MLflow user per teammate.
3. Assign experiment/model permissions per user (for example `READ`, `EDIT`, `MANAGE`) from the MLflow admin UI.
4. Have each user log in with their own account in UI/SDK (do not share one login).

Notes:
- `env/secrets.env` is only for service/bootstrap credentials, not a full team user list.
- MLflow account data and permissions are stored in Postgres.

## Routing Model

Routing is path-based through one public endpoint.

Default public endpoint values from `env/config.env`:
- `PUBLIC_FQDN=localhost`
- `NGINX_PORT=80`
- `NGINX_PORT_BIND=127.0.0.1`

Default service paths:
- `MLFLOW_BASE_PATH=mlflow`
- `RUSTFS_BASE_PATH=rustfs`
- `RUSTFS_API_BASE_PATH=rustfs-api`

Path variables are normalized by `scripts/compose.sh`:
- a leading `/` is added if missing
- trailing `/` is removed

## Env Files

Environment settings live under `env/` and are loaded by `scripts/compose.sh` in this order:
1. `env/versions.env`
2. `env/config.env`
3. `env/secrets.env`

If you need a template for secrets, use `env/secrets.env.example`.

## Networking and Ports

- All services run on the shared Docker network `mlops`.
- Nginx routes to service names inside Docker (for example `mlflow:5000`, `rustfs:9001`).
- Nginx is the only web entrypoint exposed on the host:
  - `${NGINX_PORT_BIND}:${NGINX_PORT}:80`
- RustFS and MLflow are not exposed directly on host ports.
- Postgres remains internal to Docker.

Current HTTP routing:
- `${MLFLOW_BASE_PATH}` -> `mlflow:${MLFLOW_PORT}`
- `${RUSTFS_BASE_PATH}` -> `rustfs:${RUSTFS_CONSOLE_PORT}`
- `${RUSTFS_API_BASE_PATH}` -> `rustfs:${RUSTFS_PORT}`
- `/` -> small HTML index page

RustFS API note:
- `${RUSTFS_API_BASE_PATH}` is for S3-compatible API clients and integrations (authenticated requests).
- A direct browser request to `http://localhost${RUSTFS_API_BASE_PATH}/` commonly returns `403 AccessDenied` and is expected.

HTTP only for now (no TLS yet). The Nginx config is structured so HTTPS can be added later at the proxy.

## Makefile

- `make up` start services (build if needed)
- `make down` stop services
- `make ps` show service status
- `make logs` tail logs for all services
- `make logs SERVICE=nginx` tail logs for one service
- `make test` run smoke test

## Adding Another Service Behind Nginx

1. Add the service to Compose on the `mlops` network.
2. Keep it internal (prefer `expose`, avoid host `ports` unless explicitly needed).
3. Add a path variable in `env/config.env`.
4. Add Nginx locations in `nginx/default.conf.template`:
   - `location = /your-path { return 301 /your-path/; }`
   - `location /your-path/ { proxy_pass http://<docker-service-name>:<port>/; }`
   - include standard forwarding headers.

## Remote/VPN Migration Later

When moving to a shared server, update:
- `PUBLIC_FQDN` to a DNS name reachable by your VPN users
- `NGINX_PORT_BIND` to `0.0.0.0` or a specific server IP

Team members then access the same server endpoint and paths, for example:
- `http://<your-server-dns>/mlflow`

## Troubleshooting

- Service not reachable:
  - verify `make ps`
  - check `make logs` and `make logs SERVICE=nginx`
- Port conflicts on host:
  - check if another process already uses `${NGINX_PORT}`
- Remote users cannot connect:
  - verify server bind (`NGINX_PORT_BIND`) and DNS/VPN reachability
