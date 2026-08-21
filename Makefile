.PHONY: help up down ps logs test secrets-generation-test airflow-init-test airflow-project-env-bundle-test airflow-projects-list airflow-projects-validate

help:
	@echo "Make targets:"
	@echo "  make up            Start services (build if needed)"
	@echo "  make down          Stop services"
	@echo "  make ps            Show service status"
	@echo "  make logs          Tail logs (all services)"
	@echo "  make logs SERVICE=mlflow   Tail logs for one service"
	@echo "  make test          Run smoke test"
	@echo "  make secrets-generation-test  Test generated secret safety"
	@echo "  make airflow-init-test  Test Airflow bootstrap argument handling"
	@echo "  make airflow-project-env-bundle-test  Test generated Airflow project env bundle"
	@echo "  make airflow-projects-list      Show discoverable Airflow projects"
	@echo "  make airflow-projects-validate  Validate project manifests and mount setup"

up:
	./scripts/compose.sh up -d --build

down:
	./scripts/compose.sh down

ps:
	./scripts/compose.sh ps

SERVICE ?=
logs:
	./scripts/compose.sh logs --no-color --tail=200 $(SERVICE)

test:
	./scripts/test-generate-secrets-env.sh
	./scripts/test-airflow-init.sh
	./scripts/test-airflow-project-env-bundle.sh
	./scripts/smoke-test.sh

secrets-generation-test:
	./scripts/test-generate-secrets-env.sh

airflow-init-test:
	./scripts/test-airflow-init.sh

airflow-project-env-bundle-test:
	./scripts/test-airflow-project-env-bundle.sh

airflow-projects-list:
	./scripts/airflow-projects.sh list

airflow-projects-validate:
	./scripts/airflow-projects.sh validate
