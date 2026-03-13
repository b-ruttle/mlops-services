ARG PYTHON_IMAGE=python:3.11-slim
FROM ${PYTHON_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY app.py /app/app.py
COPY templates /app/templates

CMD ["/bin/sh", "-c", "gunicorn --workers 2 --threads 4 --bind 0.0.0.0:${MLFLOW_ADMIN_PORT:-8080} app:app"]
