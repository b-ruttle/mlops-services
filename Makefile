.PHONY: help up down ps logs test

help:
	@echo "Make targets:"
	@echo "  make up            Start services (build if needed)"
	@echo "  make down          Stop services"
	@echo "  make ps            Show service status"
	@echo "  make logs          Tail logs (all services)"
	@echo "  make logs SERVICE=mlflow   Tail logs for one service"
	@echo "  make test          Run smoke test"

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
