# MLOps Services

Local MLOps services for development and testing, orchestrated with Docker Compose.

The stack includes:
- MLflow (tracking server)
- MLflow Admin App (simple user management UI for MLflow auth users)
- Airflow (scheduler and DAG UI for local orchestration)
- Postgres (MLflow backend store plus separate auth and Feast DBs)
- RustFS (S3-compatible object store)
- Nginx (single HTTP entrypoint with path-based routing)

## Quickstart

1. Configure secrets:
```bash
./scripts/generate-secrets-env.sh
# or copy the example and edit it manually:
# cp env/secrets.env.example env/secrets.env
```
Set strong values for:
- `MLFLOW_FLASK_SERVER_SECRET_KEY`
- `MLFLOW_AUTH_ADMIN_PASSWORD`
- `MLFLOW_ADMIN_APP_PASSWORD`
- `MLFLOW_ADMIN_APP_SECRET_KEY`
- `AIRFLOW_FERNET_KEY`
- `AIRFLOW_SECRET_KEY`
- `AIRFLOW_ADMIN_PASSWORD`

Generate `AIRFLOW_FERNET_KEY` with:
```bash
python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

2. Start the stack:
```bash
make up
```

3. Open services (no hosts-file edits required by default):
- `http://localhost/mlflow`
- `http://localhost/mlflow-admin` (admin app login)
- `http://localhost/airflow` (Airflow UI)
- `http://localhost/rustfs` (RustFS console)
- `http://localhost/` (simple index page)

Credential map:
- MLflow UI: sign in with a personal MLflow user account, not the bootstrap admin account
- MLflow Admin App: `MLFLOW_ADMIN_APP_USERNAME` / `MLFLOW_ADMIN_APP_PASSWORD`
- Airflow UI: `AIRFLOW_ADMIN_USERNAME` / `AIRFLOW_ADMIN_PASSWORD`
- RustFS Console: `RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY`

Storage note:
- The RustFS web console is exposed at `/rustfs`.
- The S3-compatible API remains internal to the Docker network and is used by MLflow at `http://rustfs:${RUSTFS_PORT}`.
- If you need host-side S3 access later, add an explicit port publish or a dedicated proxy route.

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
- `MLFLOW_AUTH_POSTGRES_DB` (in `env/config.env`) names the Postgres DB used by MLflow auth (default `mlflow_auth`).
- `FEAST_POSTGRES_DB` (in `env/config.env`) names the Postgres DB reserved for Feast/offline feature store metadata (default `feast`).

Recommended team workflow:
1. Keep one admin account for platform maintenance.
2. Create one MLflow user per teammate.
3. Assign experiment/model permissions per user (for example `READ`, `EDIT`, `MANAGE`) from the MLflow admin UI.
4. Have each user log in with their own account in UI/SDK (do not share one login).

Notes:
- `env/secrets.env` is only for service/bootstrap credentials, not a full team user list.
- MLflow auth account data follows `MLFLOW_AUTH_DATABASE_URI` and is expected to use Postgres (`postgresql+psycopg2://...`) in this setup.
- Keep auth in Postgres on the same server but a separate DB (for example `mlflow_auth`), because MLflow tracking and auth both use Alembic and should not share one DB.
- Feast should use its own Postgres DB (for example `feast`) rather than sharing the MLflow tracking or auth DBs.
- The MLflow Admin App authenticates with its own login (`MLFLOW_ADMIN_APP_USERNAME`/`MLFLOW_ADMIN_APP_PASSWORD`) and then calls MLflow APIs using `MLFLOW_AUTH_ADMIN_USERNAME`/`MLFLOW_AUTH_ADMIN_PASSWORD`.
- The MLflow Admin App user list is sourced from the auth database (no API fallback path).
- The `postgres-init` one-shot service creates the extra auth/Feast DBs if they are missing, so this works for both fresh and existing Postgres volumes.

## Routing Model

Routing is path-based through one public endpoint.

Default public endpoint values from `env/config.env`:
- `PUBLIC_FQDN=localhost`
- `NGINX_PORT=80`
- `NGINX_PORT_BIND=127.0.0.1`

Default service paths:
- `MLFLOW_BASE_PATH=mlflow`
- `MLFLOW_ADMIN_BASE_PATH=mlflow-admin`
- `AIRFLOW_BASE_PATH=airflow`
- `RUSTFS_BASE_PATH=rustfs`

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
- RustFS console, MLflow, mlflow-admin, and Airflow are not exposed directly on host ports.
- RustFS's S3-compatible API is also not exposed on a public Nginx path.
- Postgres remains internal to Docker.

Current HTTP routing:
- `${MLFLOW_BASE_PATH}` -> `mlflow:${MLFLOW_PORT}`
- `${MLFLOW_ADMIN_BASE_PATH}` -> `mlflow-admin:${MLFLOW_ADMIN_PORT}`
- `${AIRFLOW_BASE_PATH}` -> `airflow-webserver:${AIRFLOW_PORT}`
- `${RUSTFS_BASE_PATH}` -> `rustfs:${RUSTFS_CONSOLE_PORT}`
- `/` -> small HTML index page

## Airflow

Airflow is configured for local development with:
- `LocalExecutor`
- Postgres metadata stored in `${AIRFLOW_POSTGRES_DB}`
- one-shot bootstrap containers that create the metadata DB, run migrations, and ensure an admin user exists
- the web UI published only through nginx at `${AIRFLOW_BASE_PATH}`
- automatic DAG discovery from a shared `mlops-examples` repo plus any projects registered under `AIRFLOW_PROJECTS_DIR`
  via project-owned manifest files

Default bootstrap credentials come from `env/secrets.env`:
- `AIRFLOW_ADMIN_USERNAME` (default `admin`)
- `AIRFLOW_ADMIN_PASSWORD`

Airflow project discovery now uses:

- `MLOPS_EXAMPLES_DIR`: shared example repo checkout resolved by `scripts/compose.sh` from your shell or the default sibling repo layout
- `AIRFLOW_PROJECTS_DIR=..`: host-side root that contains sibling project repos

At runtime, Airflow mounts the whole `AIRFLOW_PROJECTS_DIR` root once, then a startup wrapper scans each repo under that root for a project-owned `.airflow-project.env` manifest before `airflow-init`, `airflow-webserver`, or `airflow-scheduler` starts. For every matching repo, the wrapper adds that repo's DAG directory into `/opt/airflow/dags`, sources any optional project env file, and exports a derived `<PROJECT>_REPO_HOST_DIR` for DockerOperator mounts.

The shared `mlops-examples/dags` source is always included automatically, so existing example DAGs keep working without any extra registration step.

### Airflow Project Registration

Each project self-registers from its own repo by adding a manifest file named `.airflow-project.env` at the repo root. A template lives at [`airflow/project-manifest.example.env`](/mnt/c/Users/brent/Documents/mlops/repos/mlops-services/airflow/project-manifest.example.env).

```dotenv
PROJECT_NAME=my-project
DAGS_DIR=dags
ENV_FILE=airflow/airflow.env
```

Fields:

- `PROJECT_NAME`: optional display and symlink name. If omitted, the repo directory name is used.
- `DAGS_DIR`: optional repo-relative DAG directory. Defaults to `dags`.
- `ENV_FILE`: optional repo-relative env file that should be sourced into the Airflow processes.

Path rules:

- The manifest itself must live at the project repo root inside `AIRFLOW_PROJECTS_DIR`.
- `DAGS_DIR` and `ENV_FILE` are resolved relative to that repo root.
- Project env vars are loaded into `airflow-init`, `airflow-webserver`, and `airflow-scheduler` in alphabetical repo order.
- Discovery automatically exports `<PROJECT>_REPO_HOST_DIR`, where `<PROJECT>` is `PROJECT_NAME` uppercased with non-shell-name characters normalized to underscores. For example, `PROJECT_NAME=gnss` produces `GNSS_REPO_HOST_DIR`, and `PROJECT_NAME=my-project` produces `MY_PROJECT_REPO_HOST_DIR`.
- `<PROJECT>_REPO_HOST_DIR` is derived from the host-side checkout path under `AIRFLOW_PROJECTS_DIR`, not from the internal Airflow container path under `/opt/airflow/projects-root`. DAGs can pass it directly to DockerOperator bind mounts such as `${GNSS_REPO_HOST_DIR}:/work`.
- Prefer namespaced variables like `MY_PROJECT_RUNNER_IMAGE` so two projects do not fight over generic names. Do not define `<PROJECT>_REPO_HOST_DIR` manually in the project env file; discovery writes the authoritative value.

### Onboarding A New Project Repo

Recommended operator workflow:

1. Check out the project repo somewhere on the host.
2. Make sure that checkout lives under `AIRFLOW_PROJECTS_DIR` or adjust `AIRFLOW_PROJECTS_DIR` so it includes that repo root.
3. Add `.airflow-project.env` at the project repo root.
4. If the DAG code needs repo-specific env, add a project env file in that same repo and reference it with `ENV_FILE=...`.
5. Run `make airflow-projects-validate`.
6. Run `make up` or restart the Airflow services.
7. Open the Airflow UI and confirm the new DAGs appear.

Generic example project manifest:

```dotenv
# in /path/to/repo/.airflow-project.env
PROJECT_NAME=my-project
DAGS_DIR=dags
ENV_FILE=airflow/airflow.env
```

Generic example project env file:

```dotenv
# in /path/to/repo/airflow/airflow.env
MY_PROJECT_RUNNER_IMAGE=my-project-runner
MY_PROJECT_CONFIG_PATH=configs/dev.yaml
```

The generated Airflow project env bundle will include:

```dotenv
export MY_PROJECT_REPO_HOST_DIR=/path/to/repo
```

### Helper Commands

- `make airflow-projects-list` shows the built-in shared DAG source plus every discoverable project manifest under `AIRFLOW_PROJECTS_DIR`.
- `make airflow-projects-validate` checks that every project-owned manifest points at a real DAG directory and optional env file.

### Design Choice And Tradeoffs

Recommended implementation: one shared root mount plus a small Airflow bootstrap wrapper that discovers project-owned manifests.

Why this is the cleanest option here:

- `mlops-services` no longer needs a change for every new project repo.
- Each project keeps its DAG registration and optional Airflow env config in its own repo, which is where that knowledge belongs.
- Airflow still wants one DAG root. The startup wrapper solves that by rebuilding `/opt/airflow/dags` from discovered repo manifests every time a container starts.
- Optional project env files fit the same pattern cleanly because the whole repo root is already mounted.

Why not direct hardcoded multi-directory DAG mounts in the base compose:

- Every new repo would require editing shared Compose YAML.
- That does not scale for a shared server with many project repos.

Why not a central registration directory in `mlops-services`:

- It still requires a platform repo change for every new project.
- It splits project-specific Airflow metadata away from the project that owns the DAGs.

Why not a host-side sync or symlink-only approach:

- Host symlinks inside one bind-mounted folder do not reliably expose arbitrary repo paths inside containers unless those repos are also mounted separately.
- Copy/sync workflows add another reconciliation step and drift risk for local development.

Known limitations:

- Projects must live under the mounted `AIRFLOW_PROJECTS_DIR` root. If a repo lives elsewhere, either move it under that root or point `AIRFLOW_PROJECTS_DIR` at a higher-level directory that contains all relevant repos.
- Project env files are global to the Airflow processes. Use namespaced variable names to avoid collisions.
- If two repos ship DAGs with the same Airflow `dag_id`, Airflow will still treat that as a conflict.

HTTP only for now (no TLS yet). The Nginx config is structured so HTTPS can be added later at the proxy.

## Makefile

- `make up` start services (build if needed)
- `make down` stop services
- `make ps` show service status
- `make logs` tail logs for all services
- `make logs SERVICE=nginx` tail logs for one service
- `make test` run smoke test
- `make airflow-projects-list` show registered Airflow project DAG sources
- `make airflow-projects-validate` validate Airflow project registrations and regenerate the project override compose file

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
