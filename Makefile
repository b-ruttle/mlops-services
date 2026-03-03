.PHONY: help up down ps logs test vault-seed vault-render

help:
	@echo "Make targets:"
	@echo "  make up            Start services (build if needed)"
	@echo "  make down          Stop services"
	@echo "  make ps            Show service status"
	@echo "  make logs          Tail logs (all services)"
	@echo "  make logs SERVICE=mlflow   Tail logs for one service"
	@echo "  make test          Run smoke test"
	@echo "  make vault-seed    Seed local Vault KV and deploy policy"
	@echo "  make vault-render  Render .runtime/secrets.env from Vault KV"

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

vault-seed:
	./scripts/vault/seed-dev.sh

vault-render:
	./scripts/vault/render-secrets.sh
