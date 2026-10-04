# AI_INSTRUCTIONS

## Deployer Hardening Conventions

- [CRITICAL] Canonical `docker-compose.yml` must run the backend API with `ASPNETCORE_ENVIRONMENT=Production` and set production-like defaults for `Swagger__Enabled=false`, `ForwardedHeaders__Enabled=true`, `RateLimiting__Enabled=true`, and `AllowedHosts`.
- [CRITICAL] `docker-compose.dev.yml` is the only file that overrides these to development-friendly values (`ASPNETCORE_ENVIRONMENT=Development`, `Swagger__Enabled=true`, `RateLimiting__Enabled=false`, `ForwardedHeaders__Enabled=false`, `AllowedHosts=*`, `BASIC_AUTH_ENABLED=false`).
- [MANDATORY] Rate limiter environment variables use ASP.NET Core double-underscore convention: `RateLimiting__Enabled`, `RateLimiting__Auth__PermitLimit`, `RateLimiting__Auth__WindowMinutes`, `RateLimiting__Ingest__PermitLimit`, `RateLimiting__Ingest__WindowMinutes`.
- [MANDATORY] `AllowedHosts` is set via env var and must include both the internal Docker service name (`api`) and the public API hostname. Canonical compose uses `AllowedHosts=api;${AllowedHosts:-libnode-api}`. Never leave it as `*` in production compose.
- [MANDATORY] `TRANSLATOR_BASIC_AUTH_ENABLED=true` and explicit non-default credentials are required in production; `admin/admin`, `placeholder-*`, `changeme`, and empty strings are rejected by translator startup validation.
- [MANDATORY] `TRANSLATOR_CSRF_SECRET` must be set to a high-entropy value in production; do not use the fallback dev secret.
- [MANDATORY] Use `docker compose --env-file .env.example config --quiet` for canonical validation and `.env.verify.example` with the verify overlay for disposable validation; never paste resolved `docker compose config` output because it may contain env values.
- [MANDATORY] Use the `docker-compose.verify.yml` overlay with `.env.verify.example` for disposable PostgreSQL/Redis/MinIO/translator Playwright storage, backend migration (`api-migrate`), backend regression tests (`api-tests`), and hardened translator smoke checks.
- [MANDATORY] See `VERIFY.md` for the full Phase 6 verification matrix: build all images, run migrations, run backend tests, run translator init, and smoke web/worker health.
- [MANDATORY] Local verification targets a trusted local subnet. Document any trusted-subnet assumptions separately from production-like hardening expectations.

## Makefile and Daily Operations

- [MANDATORY] The `Makefile` is the primary command surface for operating the stack. Prefer it over long `docker compose` commands.
- [MANDATORY] Common commands:
  - `make up` — start the stack in the background.
  - `make down` — stop the stack.
  - `make restart` — stop, rebuild all images, and start the stack. This is the default command to apply code changes.
  - `make build` — rebuild all images without restarting.
  - `make migrate` — apply EF Core migrations via the `api-migrate` service. This is also run automatically during `make up` / `make restart`.
  - `make verify` — validate the canonical Compose config without exposing secrets.
  - `make test` — run the full backend regression suite against the verify overlay.
  - `make logs` — follow logs; target a service with `ARGS='-f api'`.
  - `make status` — show running containers.
- [CRITICAL] `make restart` must be used after any backend, frontend, or translator code change. It rebuilds the affected images and restarts the services.
- [CRITICAL] Backend EF Core migrations are applied automatically on every `make up` / `make restart` by the `api-migrate` service. The `api` service depends on `api-migrate` completing successfully before it starts.
- [CRITICAL] If the production database is in an inconsistent migration state (e.g., tables exist but `__EFMigrationsHistory` is missing entries), use the manual helper scripts in `migrations/` only after understanding the current schema. These scripts are operational escape hatches, not standard procedure.
- [MANDATORY] `.env` is local-only and ignored. Use `.env.example` as the documented template. Never commit `.env` or `.env.verify`.
- [MANDATORY] `migrations/` helper scripts are operational tools; they do not belong in the canonical application path. Keep them updated if the EF migration baseline changes.

## Workspace Guardrails

- Read `/home/qustust/projects/libnodeProject/AGENTS.md` before this file.
- This repo is the Docker Compose orchestration and verification repository for LibNode.
- Do not place backend, frontend, translator application logic, runtime hardening fixes, EF migrations, Prisma schema changes, or UI changes in this repo.
- Before editing or committing on user request, run `git status --short`, `git diff`, and `git diff --staged` from `libnode-deployer/`.
- Never read, print, commit, or summarize real `.env`, `.env.local`, `.env.verify`, data mounts, Playwright storage state, browser profiles, logs, or expanded Compose config.
- Use `docker compose config --quiet` for shared Compose validation. Do not paste full `docker compose config` output.
- Verification examples must use placeholders only. Use `.env.verify.example` for committed verify inputs and `.env.verify` only as ignored local runtime input.
- Keep Phase 1 changes to workspace guidance, verification scaffolding, ignore hygiene, and docs. Production-like runtime hardening belongs to later plans.

## Disposable Translator Queue Acceptance

- [MANDATORY] `make verify-translator-queue` and `make test-translator-queue` are the focused Make surface; modes are only `integration` (default), `offline`, `checks`, `failure-check`. Do not delegate them to production `COMPOSE`/`ENV_FILE`/`VERIFY_ENV_FILE` or arbitrary commands.
- [CRITICAL] Always generate a fresh, non-overridable `libnode-translator-queue-*` project, sanitize Docker/Compose env, use only `.env.verify.example` and the existing verify overlay/profile, and collision-check its resource labels before registering ownership/cleanup. Start only `postgres-translator-verify`, `redis-verify` and tools `translator-tests`; offline/checks start no dependencies. Never operate live translator/API/frontend/init services from these targets.
- [CRITICAL] `translator-tests` has only explicit TEST inputs, no production env anchors, live env file, host ports, bind mounts or provider settings, and only an internal test network. Dependencies keep their existing default network too. Tests/config are tools-stage-only; keep runtime and generated Vite flow unchanged.
- [MANDATORY] Guard explicit `NODE_ENV=test`, `TEST_TRANSLATOR_QUEUE=1`, exact disposable PostgreSQL/Redis TEST endpoints before migration/client setup; no production URL fallback. Migrate in the tools container with installed CLI binaries and CLI-child-only validated `DATABASE_URL`. Keep ordinary translator test discovery offline.
- [CRITICAL] Trap EXIT/INT/TERM before build/startup, clean only the generated project's containers/networks/volumes and prove labels absent afterwards; preserve genuine failure status. No prune, flush, obliterate, truncate or unscoped delete. `failure-check` is green only after its expected post-migration exit 42 and successful cleanup, not an arbitrary failure.
- [MANDATORY] Queue pause is global: active work may finish, all projects' pending translations wait, other-project data/status/history survives, and any project Resume unpauses globally. Verify real service/repository/registered-worker behavior with controlled external processors, serial scenarios and unchanged 35-second retry waits; do not claim live admin/auth/LLM/source or production migration proof.
- [MANDATORY] Test-only harness edits rebuild tools via the focused target, without restarting the live stack. If a regression requires runtime source changes, coordinate the required `make restart` separately and report isolated evidence apart from live acceptance.

## Disposable Reader Browser Acceptance

- Use `make verify-reader-e2e` / `make test-reader-e2e`; modes: `integration`, `checks`, `backend-unit`, `failure-check`. The script fixes the default same-host Docker context, example input file, service allowlists and generated `libnode-reader-e2e-*` project; never use live Make/Compose/env overrides.
- Dedicated `reader-e2e-*` services do not inherit live container names, ports, mounts or env anchors. API/web/migration/runner use only an internal network. Explicit service selection and `--no-deps` are mandatory; enabling a profile alone does not isolate live services.
- Reuse actual API/Nuxt Docker targets and translator's existing Playwright tooling stage only (no translator app or outbound calls). EF/test tooling restores at image build time via `additional_contexts`, not on the internal runtime network. Guard exact disposable migration/HTTP inputs before mutation.
- Never inspect/export sessions, cookies, headers, browser storage, profiles or runtime logs; no screenshots/traces/HAR/video. Reports are static classifications/counts only. Cleanup traps must prove owned containers/networks/volumes absent on success/failure/interruption; exit 42 requires the post-fixture marker as well as successful cleanup.
- Isolated acceptance is not live acceptance. Do not restart or modify the shared stack from these test targets; applying runtime changes requires a separately coordinated `make restart`. Parent planning remains local-only.
