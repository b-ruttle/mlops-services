#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE="${ROOT_DIR}/scripts/compose.sh"

ENV_DIR="${ENV_DIR:-${ROOT_DIR}/env}"
set -a
source "${ENV_DIR}/versions.env"
source "${ENV_DIR}/config.env"
source "${ENV_DIR}/secrets.env"
set +a

cd "${ROOT_DIR}"

if ! "${COMPOSE}" up -d --build; then
  echo "ERROR: docker compose up failed"
  "${COMPOSE}" ps || true
  "${COMPOSE}" logs --no-color --tail=200 nginx || true
  "${COMPOSE}" logs --no-color --tail=200 postgres || true
  "${COMPOSE}" logs --no-color --tail=200 rustfs || true
  "${COMPOSE}" logs --no-color --tail=200 mlflow || true
  exit 1
fi

MLFLOW_PORT="${MLFLOW_PORT:-5000}"
RUSTFS_PORT="${RUSTFS_PORT:-9000}"
MLFLOW_S3_ENDPOINT_URL="${MLFLOW_S3_ENDPOINT_URL:-http://rustfs:${RUSTFS_PORT}}"
NGINX_PORT="${NGINX_PORT:-80}"
PUBLIC_FQDN="${PUBLIC_FQDN:-localhost}"
MLFLOW_BASE_PATH="${MLFLOW_BASE_PATH:-mlflow}"
if [[ "${MLFLOW_BASE_PATH}" != /* ]]; then
  MLFLOW_BASE_PATH="/${MLFLOW_BASE_PATH}"
fi
MLFLOW_BASE_PATH="${MLFLOW_BASE_PATH%/}"
if [[ -z "${MLFLOW_BASE_PATH}" ]]; then
  echo "ERROR: MLFLOW_BASE_PATH must not be empty or '/'."
  exit 1
fi

PUBLIC_MLFLOW_URI="http://${PUBLIC_FQDN}"
LOCAL_PROXY_URI="http://127.0.0.1"
if [[ "${NGINX_PORT}" != "80" ]]; then
  PUBLIC_MLFLOW_URI="${PUBLIC_MLFLOW_URI}:${NGINX_PORT}"
  LOCAL_PROXY_URI="${LOCAL_PROXY_URI}:${NGINX_PORT}"
fi
PUBLIC_MLFLOW_URI="${PUBLIC_MLFLOW_URI}${MLFLOW_BASE_PATH}"
LOCAL_MLFLOW_URI="${LOCAL_PROXY_URI}${MLFLOW_BASE_PATH}"
INTERNAL_MLFLOW_URI="http://mlflow:${MLFLOW_PORT}"

echo "Waiting for MLflow to respond via proxy path ${MLFLOW_BASE_PATH} ..."
for _ in {1..60}; do
  if curl -fsSL "${LOCAL_MLFLOW_URI}/" >/dev/null 2>&1; then
    echo "MLflow is up."
    break
  fi
  sleep 2
done

if ! curl -fsSL "${LOCAL_MLFLOW_URI}/" >/dev/null 2>&1; then
  echo "MLflow did not become ready in time."
  "${COMPOSE}" ps || true
  "${COMPOSE}" logs --no-color --tail=200 nginx || true
  "${COMPOSE}" logs --no-color --tail=200 mlflow || true
  exit 1
fi

MLFLOW_URI="${1:-${INTERNAL_MLFLOW_URI}}"

"${COMPOSE}" exec -T mlflow python - <<PY
import mlflow
from mlflow.tracking import MlflowClient

mlflow.set_tracking_uri("${MLFLOW_URI}")
experiment_name = "smoke-test"
client = MlflowClient()
exp = client.get_experiment_by_name(experiment_name)
if exp is not None and exp.lifecycle_stage == "deleted":
    client.restore_experiment(exp.experiment_id)
mlflow.set_experiment(experiment_name)

artifact_bucket = "${MLFLOW_ARTIFACT_BUCKET}"
s3_endpoint_url = "${MLFLOW_S3_ENDPOINT_URL}"

run_id = None
with mlflow.start_run() as run:
    run_id = run.info.run_id
    mlflow.log_param("ping", "pong")
    mlflow.log_metric("m", 0.123)
    with open("hello.txt", "w") as f:
        f.write("hi")
    mlflow.log_artifact("hello.txt")

print("OK: logged run + artifact to", "${MLFLOW_URI}")
print("OK: public proxy endpoint reachable at", "${PUBLIC_MLFLOW_URI}")

# Cleanup: remove local file and delete the test run + artifacts.
try:
    import os
    if os.path.exists("hello.txt"):
        os.remove("hello.txt")
except Exception as exc:
    print("WARN: could not remove hello.txt:", exc)

try:
    if run_id is not None:
        # Delete artifacts from S3-compatible storage to keep RustFS clean.
        run_info = client.get_run(run_id).info
        artifact_uri = run_info.artifact_uri
        if artifact_uri.startswith("s3://"):
            from urllib.parse import urlparse

            parsed = urlparse(artifact_uri)
            bucket = parsed.netloc
            prefix = parsed.path.lstrip("/")
        elif artifact_uri.startswith("mlflow-artifacts:"):
            bucket = artifact_bucket
            prefix = artifact_uri.split(":", 1)[1].lstrip("/")
        else:
            bucket = artifact_bucket
            prefix = ""

        import boto3

        s3 = boto3.client("s3", endpoint_url=s3_endpoint_url)
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            contents = page.get("Contents", [])
            if not contents:
                continue
            to_delete = [{"Key": obj["Key"]} for obj in contents]
            s3.delete_objects(Bucket=bucket, Delete={"Objects": to_delete})
        # Delete the run from the backend store to keep Postgres clean.
        client.delete_run(run_id)
except Exception as exc:
    print("WARN: cleanup failed:", exc)
PY
