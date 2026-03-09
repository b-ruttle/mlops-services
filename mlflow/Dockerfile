ARG PYTHON_IMAGE=python:3.11-slim
FROM ${PYTHON_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    git \
    libpq-dev \
    curl \
  && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY start-mlflow.sh /usr/local/bin/start-mlflow.sh
RUN chmod +x /usr/local/bin/start-mlflow.sh
