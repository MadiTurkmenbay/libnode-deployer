# LibNode Docker Verification

## Secret-Safe Rules

Do not run or paste full `docker compose config` output in shared summaries.

Report command and pass/fail only; do not paste resolved env values or secret-bearing logs.

`.env.verify.example` is placeholder-only and safe to commit; `.env.verify` is local-only and ignored.

Phase 1 verification checks Compose syntax and disposable dependency wiring only. It does not harden production runtime behavior.

## Quiet Compose Validation

Validate the canonical deployer Compose file without printing the expanded config:

```bash
docker compose --env-file .env.example config --quiet
```

## Verification Overlay

Validate the verification overlay with placeholder-only values and disposable dependencies:

```bash
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml config --quiet
```

Optional build smoke for affected images:

```bash
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml build api web translator-init translator-web translator-worker
```

## Backend Migration Verification

Run migrations against a disposable PostgreSQL instance. The `api-migrate` service applies all migrations before the main `api` service starts.

```bash
# Validate configuration (does not print expanded config or secrets)
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml config --quiet

# Apply migrations to a clean verify database
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate

# Clean up the disposable environment
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Backend Regression Tests

Run the backend xUnit regression suite against the same disposable PostgreSQL instance that `api-migrate` uses.

```bash
# Run migrations and then tests
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests

# Clean up the disposable environment
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Disposable Dependency Smoke

Start only the disposable PostgreSQL and Redis dependencies, inspect state locally, then clean them up. Do not paste logs or expanded config into shared summaries.

```bash
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml up -d postgres-reader-verify postgres-translator-verify redis-verify
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml ps
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Cleanup

If a verification run is interrupted, clean the disposable project before retrying:

```bash
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Local Trusted-Subnet Assumptions

LibNode is currently operated on a trusted local subnet. The following assumptions apply to local development:

- Docker Compose network is internal; containers trust each other's traffic.
- ForwardedHeaders middleware clears KnownProxies/KnownNetworks (trust Docker internal network).
- Rate limiter partitions by IP — this is practical abuse control, not DDoS defense.
- Frontend `auth_token` cookie is JavaScript-readable (not HttpOnly). XSS hardening is deferred to v2.
- Translator Basic Auth is single-user; no RBAC beyond admin/non-admin distinction.

## Full Phase 6 Verification Matrix

Run the complete v1 closeout matrix against the verify overlay. Use the actual local `.env.verify` file (ignored, never paste its contents).

```bash
# 1. Validate canonical Compose (no expanded output)
docker compose --env-file .env.example config --quiet

# 2. Validate verify overlay with placeholder example
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml config --quiet

# 3. Build all images
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml build --parallel api web translator-init translator-web translator-worker

# 4. Backend: apply migrations to clean disposable PostgreSQL
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate

# 5. Backend: run regression tests
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests

# 6. Translator: run migrations and seed
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init

# 7. Translator: start web and worker
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker

# 8. Translator web health check
curl -sS http://localhost:13005/health

# 9. Translator worker startup log (should show startup without external job activity)
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml logs --tail=20 translator-worker

# 10. Clean up the disposable environment
docker compose -p libnode_verify --env-file .env.verify -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

Report command and pass/fail only; do not paste resolved env values, full Compose output, or secret-bearing logs.

## Production-Like Hardening (Phases 2–5)

Since Phase 2, the canonical `docker-compose.yml` defaults to production-like runtime:

- `ASPNETCORE_ENVIRONMENT=Production` — Swagger gated by `Swagger__Enabled=false` (bound to `Swagger:Enabled`), HTTPS redirection active, ForwardedHeaders enabled.
- `BASIC_AUTH_ENABLED=true` — Translator admin requires credentials; defaults are rejected at startup.
- Rate limiting active on `/api/auth/*` (10 req/min) and `/api/reader/*` (60 req/min).
- Translator unknown errors return generic messages; internal details logged server-side.
- Translator mutating web forms have CSRF double-submit cookie protection.
- `AllowedHosts` is set to `libnode-api` by default; operators should override this to their production API hostname.

Use `docker-compose.dev.yml` to restore development-friendly behavior for local iteration:
```bash
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml up
```

## Stabilization Decisions and Honest Scope

### What v1 Stabilization Proves

- **Workspace discipline:** four separate implementation repos, parent `.planning/` local-only, Docker-first verification, and repo-specific status checks.
- **Deployment defaults:** API runs in `Production`, Swagger/ForwardedHeaders/RateLimiting are gated, translator fails closed with non-default credentials.
- **Auth surfaces:** JWT bearer auth on backend; client-created `auth_token` cookie with conditional `Secure` and `SameSite=Lax` on frontend; translator Basic Auth + CSRF for web forms.
- **Backend invariants:** EF migrations reconcile cleanly; collection add/move is idempotent/atomic; reading-progress upsert handles concurrent first writes; tags/categories protected by unique DB constraints.
- **Reader contracts:** `ChapterDetailDto` exposes `previousChapterId`/`nextChapterId`; catalog uses `CursorStringPagedResult<T>` with deterministic sort-value + ID tie-breakers.
- **Frontend integration:** `useApiFetch` is the single API layer; `useCatalogCursor.ts` owns catalog state; DTOs mirror backend contracts.
- **Translator operational reliability:** outbound timeouts/size limits, URL policy with private-URL escape hatch, safe `ExternalServiceError` mapping, Playwright sandbox opt-in, chunking wired into translation flow.
- **Test coverage:** backend xUnit regression suite, translator Vitest/Supertest suite (auth, CSRF, outbound, chunking), and Docker smoke checks for all services.

### What v1 Stabilization Does Not Prove

- **Server-set HttpOnly cookies / refresh-token rotation** (v2: AUTH2-01, AUTH2-02).
- **Comprehensive SSRF sandbox / allowlist/denylist for outbound networking** (v2: TRSEC2-02). The current URL policy blocks IP-based private/loopback addresses but does not block hostname-based internal Docker traffic.
- **Production server migration with TLS/reverse proxy** (v2: PROD-01, PROD-02).
- **CI/CD automation** (v2: PROD-03).
- **Operational dashboards and queue reconciliation tooling** (v2: OBS-01, OBS-02).
- **Automated backend/frontend contract sync** (v2: CONTRACT-01).
- **Full UI/UX redesign or RBAC beyond single-admin Basic Auth** (v2: UI-01, ADMIN-01, TRSEC2-01).

These are explicitly deferred so v1 remains a focused stabilization milestone.

## What Phase 2 Does Not Prove

Phase 2 hardening covers deployment defaults, auth surfaces, and error safety. It does not prove:
- EF/Prisma migration correctness (Phase 3).
- Collection idempotency or reading-progress concurrency (Phase 3).
- Reader neighbor contract or catalog cursor pagination (Phase 4).
- Translator outbound timeout/size limits or chunked translation (Phase 5).
- Server-set HttpOnly session cookies (v2).
