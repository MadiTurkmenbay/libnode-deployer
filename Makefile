# LibNode Deployer Makefile
# Production-like commands for the current host.
# Adjust ENV_FILE if you use a different env file for production.

ENV_FILE ?= .env
COMPOSE = docker compose --env-file $(ENV_FILE)

.PHONY: help up down restart build logs status verify test test-translator-queue verify-translator-queue

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
	@echo "  make test-translator-queue — isolated translator lifecycle tests (QUEUE_TEST_MODE=integration|offline|checks|failure-check)"
	@echo "  make verify-translator-queue — quiet example-only queue test config validation"

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
# Uses placeholder-only .env.verify.example by default; override VERIFY_ENV_FILE locally if needed.
VERIFY_ENV_FILE ?= .env.verify.example
test:
	docker compose -p libnode_verify --env-file $(VERIFY_ENV_FILE) -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate
	docker compose -p libnode_verify --env-file $(VERIFY_ENV_FILE) -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests
	docker compose -p libnode_verify --env-file $(VERIFY_ENV_FILE) -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init
	docker compose -p libnode_verify --env-file $(VERIFY_ENV_FILE) -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker
	docker compose -p libnode_verify --env-file $(VERIFY_ENV_FILE) -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans

# These targets deliberately do not use COMPOSE, ENV_FILE or VERIFY_ENV_FILE.
QUEUE_TEST_MODE ?= integration
export QUEUE_TEST_MODE
test-translator-queue:
	@bash scripts/test-translator-queue.sh

verify-translator-queue:
	@bash scripts/test-translator-queue.sh --verify
