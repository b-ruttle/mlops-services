.PHONY: help up down ps logs test airflow-projects-list airflow-projects-validate

help:
	@echo "Make targets:"
	@echo "  make up            Start services (build if needed)"
	@echo "  make down          Stop services"
	@echo "  make ps            Show service status"
	@echo "  make logs          Tail logs (all services)"
	@echo "  make logs SERVICE=mlflow   Tail logs for one service"
	@echo "  make test          Run smoke test"
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
	./scripts/smoke-test.sh

airflow-projects-list:
	./scripts/airflow-projects.sh list

airflow-projects-validate:
	./scripts/airflow-projects.sh validate
