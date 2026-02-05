# MLOps Services

Local MLOps services for development and testing, orchestrated with Docker Compose. The stack includes MLflow, Postgres for the backend store, and RustFS as an S3-compatible artifact store, plus helper containers for bootstrapping and volume permissions.

## Quickstart

```bash
make up
```

```bash
make down
```

## Env Files

Environment settings live under `env/` and are loaded by `scripts/compose.sh` in this order:

1. `env/versions.env` (image and tooling versions)
2. `env/config.env` (ports, data dirs, buckets)
3. `env/secrets.env` (credentials and secrets)

If you need a template for secrets, see `env/secrets.env.example`.

## Ports and Data

Defaults are defined in `env/config.env` and can be overridden there.

Ports:
`MLFLOW_PORT` default `5000`, bound on `MLFLOW_PORT_BIND` (default `127.0.0.1`)  
`RUSTFS_PORT` default `9000`  
`RUSTFS_CONSOLE_PORT` default `9001`

Data persistence:
`POSTGRES_DATA_DIR` default `../../../volumes/mlops-data/postgres`  
`RUSTFS_DATA_DIR` default `../../../volumes/mlops-data/rustfs`

## Makefile

`make up`  
Start services (build if needed).

`make down`  
Stop services.

`make ps`  
Show service status.

`make logs`  
Tail logs for all services.

`make logs SERVICE=mlflow`  
Tail logs for a single service.

`make test`  
Run the smoke test.

## Services

`postgres`  
Postgres database used as the MLflow backend store. Data persists under `POSTGRES_DATA_DIR`.

`rustfs`  
S3-compatible object store for MLflow artifacts (and any other buckets you configure). Data persists under `RUSTFS_DATA_DIR`. Exposes an S3 API port and a console UI port.

`rustfs_init`  
One-shot init container that waits for RustFS, then ensures required buckets exist (`MLFLOW_ARTIFACT_BUCKET` and `DVC_BUCKET`).

`volume-permission-helper`  
One-shot container that fixes RustFS volume permissions on the host-mounted data directory.

`mlflow`  
MLflow tracking server configured to use Postgres for the backend store and RustFS for artifact storage. Exposed on `MLFLOW_PORT_BIND:MLFLOW_PORT`.

## Troubleshooting

If the stack fails to start, check:
`make ps` to see container status  
`make logs` or `make logs SERVICE=mlflow` for details

Common issues:
Port conflicts on `5000`, `9000`, or `9001`  
Missing or incorrect values in `env/secrets.env`  
RustFS volume permissions (fixed by `volume-permission-helper`)  
Postgres health check not passing yet (wait a few seconds and retry)
