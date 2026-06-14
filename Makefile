# LibNode Deployer Makefile
# Production-like commands for the current host.
# Adjust ENV_FILE if you use a different env file for production.

ENV_FILE ?= .env
COMPOSE = docker compose --env-file $(ENV_FILE)

.PHONY: help up down restart build logs status verify test

help:
	@echo "LibNode Deployer — available commands:"
	@echo "  make up       — start the stack in background"
	@echo "  make down     — stop the stack"
	@echo "  make restart  — rebuild images and restart the stack"
	@echo "  make build    — rebuild all images"
	@echo "  make migrate  — apply EF Core migrations to the database"
	@echo "  make logs     — follow logs (use ARGS='-f api' to target a service)"
	@echo "  make status   — show running containers"
	@echo "  make verify   — validate compose config without exposing secrets"
	@echo "  make test     — run backend regression tests (uses verify overlay)"

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart: down build
	$(COMPOSE) up -d

build:
	$(COMPOSE) build --parallel

migrate:
	$(COMPOSE) run --rm api-migrate

logs:
	$(COMPOSE) logs $(ARGS)

status:
	$(COMPOSE) ps

verify:
	$(COMPOSE) config --quiet

# Run the full Phase 6 verification matrix against the verify overlay.
# Requires a real .env.verify file (ignored by git).
test:
	docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate
	docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests
	docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init
	docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker
	docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
