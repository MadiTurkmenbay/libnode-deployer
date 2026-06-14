# AI_INSTRUCTIONS

## Deployer Hardening Conventions

- [CRITICAL] Canonical `docker-compose.yml` must run the backend API with `ASPNETCORE_ENVIRONMENT=Production` and set production-like defaults for `Swagger__Enabled=false`, `ForwardedHeaders__Enabled=true`, `RateLimiting__Enabled=true`, and `AllowedHosts`.
- [CRITICAL] `docker-compose.dev.yml` is the only file that overrides these to development-friendly values (`ASPNETCORE_ENVIRONMENT=Development`, `Swagger__Enabled=true`, `RateLimiting__Enabled=false`, `ForwardedHeaders__Enabled=false`, `AllowedHosts=*`, `BASIC_AUTH_ENABLED=false`).
- [MANDATORY] Rate limiter environment variables use ASP.NET Core double-underscore convention: `RateLimiting__Enabled`, `RateLimiting__Auth__PermitLimit`, `RateLimiting__Auth__WindowMinutes`, `RateLimiting__Ingest__PermitLimit`, `RateLimiting__Ingest__WindowMinutes`.
- [MANDATORY] `AllowedHosts` is set via env var (e.g., `AllowedHosts=libnode-api`) and operators must override it to their production API hostname. Never leave it as `*` in production compose.
- [MANDATORY] `TRANSLATOR_BASIC_AUTH_ENABLED=true` and explicit non-default credentials are required in production; `admin/admin`, `placeholder-*`, `changeme`, and empty strings are rejected by translator startup validation.
- [MANDATORY] `TRANSLATOR_CSRF_SECRET` must be set to a high-entropy value in production; do not use the fallback dev secret.
- [MANDATORY] Use `docker compose --env-file .env.example config --quiet` for validation; never paste resolved `docker compose config` output because it may contain env values.
- [MANDATORY] Use the `docker-compose.verify.yml` overlay with `.env.verify.example` for disposable PostgreSQL/Redis, backend migration (`api-migrate`), backend regression tests (`api-tests`), and hardened translator smoke checks.
- [MANDATORY] See `VERIFY.md` for the full Phase 6 verification matrix: build all images, run migrations, run backend tests, run translator init, and smoke web/worker health.
- [MANDATORY] Local verification targets a trusted local subnet. Document any trusted-subnet assumptions separately from production-like hardening expectations.

## Workspace Guardrails

- Read `/home/qustust/projects/libnodeProject/AGENTS.md` before this file.
- This repo is the Docker Compose orchestration and verification repository for LibNode.
- Do not place backend, frontend, translator application logic, runtime hardening fixes, EF migrations, Prisma schema changes, or UI changes in this repo.
- Before editing or committing on user request, run `git status --short`, `git diff`, and `git diff --staged` from `libnode-deployer/`.
- Never read, print, commit, or summarize real `.env`, `.env.local`, `.env.verify`, data mounts, Playwright storage state, browser profiles, logs, or expanded Compose config.
- Use `docker compose config --quiet` for shared Compose validation. Do not paste full `docker compose config` output.
- Verification examples must use placeholders only. Use `.env.verify.example` for committed verify inputs and `.env.verify` only as ignored local runtime input.
- Keep Phase 1 changes to workspace guidance, verification scaffolding, ignore hygiene, and docs. Production-like runtime hardening belongs to later plans.
