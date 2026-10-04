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

## Opt-in Translator Queue Lifecycle Tests

Run from this repository; no live stack restart or admin action is needed:

```bash
make verify-translator-queue
make test-translator-queue
make test-translator-queue # independent clean run in a newly generated project
make test-translator-queue QUEUE_TEST_MODE=offline
make test-translator-queue QUEUE_TEST_MODE=checks
make test-translator-queue QUEUE_TEST_MODE=failure-check
```

| Mode | Work | Dependencies started |
|------|------|----------------------|
| `integration` (default) | Guard, disposable Prisma migration, dedicated Vitest lifecycle suite | Only `postgres-translator-verify`, `redis-verify`, tools `translator-tests` |
| `offline` | Normal infrastructure-free `npm test` discovery | None |
| `checks` | `tsc --noEmit` and ESLint | None |
| `failure-check` | Guard and migration, deliberate exit 42, same scoped cleanup | Only the disposable PostgreSQL/Redis and test container |

These targets never use production `COMPOSE`, `ENV_FILE` or `VERIFY_ENV_FILE`. The script sanitizes Docker/Compose's environment, fixes the two Compose files, example env file and profile, and generates a non-overridable random `libnode-translator-queue-*` project. It first checks for exact-project collisions, registers cleanup before build/startup, uses bounded dependency health waits and `run --rm --no-deps`, and starts no API/frontend/MinIO/translator web/worker/init services. No test service has a host port, bind mount, live env file or provider settings. Only the test container is restricted to its internal network; existing disposable dependencies also retain their default network for the broader verify matrix.

### Endpoint and Migration Safety

The checked-in example supplies disposable `TEST_DATABASE_URL` and `TEST_REDIS_URL`. Runner, dedicated Vitest config and fixture all require `NODE_ENV=test` and `TEST_TRANSLATOR_QUEUE=1` before migration/client setup. Only `postgresql://` with host `postgres-translator-verify`, port `5432`, database path `/libnode_translator_verify` and credential-free `redis://redis-verify:6379/15` are accepted. Missing inputs, other schemes/hosts/ports/paths, query/fragment and Redis userinfo fail with variable-only errors. Production `DATABASE_URL`/`REDIS_URL` never satisfy this guard.

The tools container uses installed local Prisma/Vitest binaries, not downloading `npx`. A sanitized Prisma CLI child alone receives `DATABASE_URL` from validated `TEST_DATABASE_URL` for `migrate deploy`. Tests connect through explicit Prisma 6 datasource/Ioredis values without `getConfig`, dotenv, singletons or production app context. Default `npm test` excludes the infrastructure directory. Tests/config are copied only into tools after application compilation; lean runtime and Docker Vite generation remain unchanged.

### What the Suite Proves

- Real production `QueueService`, `ProjectService`, repositories, queue registry, BullMQ/Redis and Prisma/PostgreSQL, including actual `registerWorkers` failure lifecycle; only external processors are controlled doubles.
- Exact pending cleanup counts and idempotence from initially unpaused/already-paused queues; ordinary/paused, delayed and prioritized jobs; only owned `QUEUED` translation JobRuns and `QUEUED` chapter reset/error clearing.
- Active/RUNNING work and locks, FAILED/SUCCEEDED history, non-translation work and other-project jobs/rows/status survive.
- Actual Resume requeues eligible failed/cleared chapters once in the configured range, excludes retained queued/translating/completed-status/out-of-range work, and consecutive Resume preserves job/run IDs and counts.
- Four in-place attempts on the same job/run, persisted RETRYING then FAILED attempt 4/error/timestamps/progress, no premature cleanup, retained failed history and a fresh run on Resume. The unchanged 5/10/20-second real waits take approximately 35 seconds; build/startup time is additional.
- **Shared pause, not project-specific pause:** final failure pauses the global translation queue for every project. An already-active B translation can finish while B's next pending translation waits. B's DB project status need not become `PAUSED`. Resume of A (or any project) unpauses globally.

This does **not** verify live LLM/browser/source/reader integrations, admin HTTP/auth/CSRF behavior, production migration or a live image refresh. Test-only edits rebuild tools via the focused target; a proven runtime source fix needs a separately coordinated `make restart`, not a silent live operation during isolated acceptance.

### Success and Failure Cleanup

Fixture teardown releases gates and closes workers before queues and caller-owned Redis/Prisma, removes only tracked jobs/rows, deletes owned JobRuns before SetNull-linked projects, checks no fixture residues and restores test queue pause between serial cases. Never flush Redis, obliterate queues, truncate tables or issue unscoped deletes.

On success, assertion/build/migration failure or handled interruption, the script runs `down --volumes --remove-orphans` for **only its generated project**, then checks Docker project labels for remaining containers/networks/volumes. Build images/cache are retained for repeatability; no prune is performed. Cleanup failure is always nonzero. `failure-check` passes only for the deliberate post-migration exit 42 **and** successful absence checks; unrelated failures remain nonzero. Report mode, command, counts and cleanup PASS/FAIL only, never expanded config, connection values or runtime logs.

## Opt-in Reader Account/Profile/Collection Browser Checks

```bash
make verify-reader-e2e
make test-reader-e2e READER_E2E_MODE=checks
make test-reader-e2e READER_E2E_MODE=backend-unit
make test-reader-e2e
make test-reader-e2e # second independent disposable run
make test-reader-e2e READER_E2E_MODE=failure-check
```

The runner uses actual production ASP.NET/Nuxt builds and headless Chromium against a fresh PostgreSQL database. These commands never operate live services: generated `libnode-reader-e2e-*` project, sanitized same-host Docker default context, fixed `.env.verify.example`, dedicated services without fixed container names, ports or live mounts, and explicit service selection/`--no-deps`. API/web/migration/runner have only an internal network. The disposable PostgreSQL also retains its existing default network for compatibility with the broader verify matrix. Only frontend `tests/e2e` source is mounted read-only into the existing translator Playwright tooling stage; no translator application is imported or started.

Compose/Buildx must support `additional_contexts` and `dockerfile_inline`. Migration image derives from the real backend SDK build; pinned EF tooling and test packages restore at build time. Migration checks the opt-in and exact disposable connection before applying real EF migrations. Browser startup likewise rejects any alternate endpoint, project marker, fixture key or mode before importing Playwright or making requests. No production fallback or runtime downloads. `checks` runs offline Vitest and 2 positive/39 negative pure guard vectors, without infrastructure. `backend-unit` filters only the in-memory collection service tests, without DB dependencies.

### Coverage and Boundaries

| Surface | Checks |
|---|---|
| Real UI + BFF | Register; mismatch/short-password validation; duplicate username/email feedback; wrong-password feedback; login/logout/relogin |
| Profile UI + SSR | Direct document heading, hydration, reload and a new page sharing the automatic session; profile update/conflict and persisted name |
| Behavioral session renewal | Independently UI-login an untouched control and primary session; at approximately +40s update primary profile, at +65s require control `GET /api/me` = 401 and updated primary GET/SSR/reload still authenticated |
| Collection UI | Create two primary folders; add/move; renamed folder/name status; active-folder click removes; populated-folder deletion confirmation; desktop/mobile controls and no horizontal overflow |
| Authoritative BFF API | Exact counts/detail/membership/status, repeat-add no-op (not repeat-click UI), foreign detail 404 and mutations 403, invalid name 400, missing rename/delete 404, anonymous protected API denial |
| Independence/cascade | Separately UI-register/login another fixture user; its same-book membership survives first-user move/rename/remove/delete and forbidden writes; books and remaining folder survive deletion |
| Response leak guard | Successful auth/profile PUT JSON keys exactly match UserDto; profile GET keys match UserProfileDto. No token values are accessed, printed or compared |

The one-minute JWT lifetime is **test-only** and uses the unchanged backend's zero clock skew. Real waiting proves that a profile PUT replaces the BFF session behaviorally, not merely that the DB name changed. Login occurs only at explicit scenario boundaries; it cannot mask a renewal assertion. Session jars are handled automatically by Playwright `BrowserContext.request`; tests never read cookies, Set-Cookie, Authorization, browser storage or profiles, nor construct reader Bearer headers. Fixture book/chapter creation uses only the public ingest API with an example-only key; fixture accounts use UI registration. This is not translator publication evidence.

No screenshots/traces/video/HAR or raw browser/application logs. Reports contain only static scenario IDs, whitelisted failure classes, UI/API/infra counts and cleanup flags. The required inventory must be complete with no skips/zero-case success; failures are nonzero. `failure-check` is not browser coverage: it requires exit 42 **and** its static post-fixture marker after ingest succeeded, followed by cleanup.

### Cleanup and Live Acceptance

EXIT/INT/TERM traps are registered before build/startup. Teardown closes ephemeral browser contexts and removes only the generated project's containers/networks/volumes, then independently checks exact-project labels are absent. No prune, shared SQL cleanup or runtime-data deletion. Build images/cache remain for repeatability. Every independent run, including deliberate failure, must report containers=0/networks=0/volumes=0; cleanup failure is always nonzero.

This proves isolated rebuilt applications, not a live image refresh or public production readiness. Test-only changes need isolated builds only; runtime changes require a separately coordinated `make restart` for live acceptance. Optional live reader access for the operator is `http://192.168.0.106:3001`; internal test service DNS is not a user-facing link. Working data, real env inputs, paid LLM/source calls and translator authentication remain untouched. Progress, quotes, notifications, upload storage and translator-to-reader publication are outside this slice.

## Cleanup (Broader Verify Matrix)

If a verification run is interrupted, clean the disposable project before retrying:

```bash
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

## Local Trusted-Subnet Assumptions

LibNode is currently operated on a trusted local subnet. The following assumptions apply to local development:

- Docker Compose network is internal; containers trust each other's traffic.
- ForwardedHeaders middleware clears KnownProxies/KnownNetworks (trust Docker internal network).
- Rate limiter partitions by IP — this is practical abuse control, not DDoS defense.
- Frontend `auth_token` cookie is HttpOnly and set by Nuxt BFF auth routes; browser JavaScript must not read or receive JWTs.
- Translator Basic Auth is single-user; no RBAC beyond admin/non-admin distinction.

## Full Phase 6 Verification Matrix

Run the complete v1 closeout matrix against the verify overlay. The checked-in `.env.verify.example` is placeholder-only; if you override it locally with `.env.verify`, never paste its contents.

```bash
# 1. Validate canonical Compose (no expanded output)
docker compose --env-file .env.example config --quiet

# 2. Validate verify overlay with placeholder example
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml config --quiet

# 3. Build all images
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml build --parallel api web translator-init translator-web translator-worker

# 4. Backend: apply migrations to clean disposable PostgreSQL
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-migrate

# 5. Backend: run regression tests
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm api-tests

# 6. Translator: run migrations and seed
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml run --rm translator-init

# 7. Translator: start web and worker
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml up -d translator-web translator-worker

# 8. Translator web health check
curl -sS http://localhost:13005/health

# 9. Translator worker readiness
# Use `docker compose ... ps translator-worker` and report pass/fail only; do not paste logs.

# 10. Clean up the disposable environment
docker compose -p libnode_verify --env-file .env.verify.example -f docker-compose.yml -f docker-compose.verify.yml down -v --remove-orphans
```

Report command and pass/fail only; do not paste resolved env values, full Compose output, or secret-bearing logs.

## Production Deployment with External Domain

When LibNode is served through a reverse proxy (Nginx, Traefik, Caddy) on a public domain,
the canonical Compose defaults must be overridden in the real `.env` file:

```bash
# libnode-deployer/.env (local-only, ignored by git)
CORS_ORIGIN=https://libnode.qustust.ru
AllowedHosts=libnode.qustust.ru
ForwardedHeaders__Enabled=true
Swagger__Enabled=false
```

Key points:

- `AllowedHosts` must include the internal Docker service host `api` for Nuxt SSR/BFF requests.
  The canonical Compose value is `api;${AllowedHosts:-libnode-api}`. If backend is also exposed
  directly through a reverse proxy, set `AllowedHosts` to that public backend hostname.
- `ForwardedHeaders__Enabled=true` lets the API see the original client protocol and host
  through `X-Forwarded-Proto` / `X-Forwarded-Host` headers. Configure the reverse proxy to
  forward these headers and trust the Docker network (the default clears `KnownProxies`/`KnownNetworks`).
- `CORS_ORIGIN` should be the exact HTTPS origin of the reader frontend for direct backend access.
  The main browser auth-flow uses same-origin Nuxt BFF and does not require a separate browser API base.
- Browser API traffic goes to same-origin Nuxt BFF (`/api/*`). `NUXT_PUBLIC_API_BASE`
  remains the internal server-side backend URL (`http://api:8080` in Compose).

Example minimal Nginx reverse-proxy snippet for a single-domain setup:

```nginx
server {
    listen 443 ssl;
    server_name libnode.qustust.ru;

    # SSL certificates here

    location / {
        proxy_pass http://127.0.0.1:3001;  # Nuxt frontend + same-origin /api BFF
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

For the translator admin, expose `translator-web` on a separate port or host
(e.g., `https://translator.libnode.qustust.ru` mapped to host port `3005`):

```bash
TRANSLATOR_WEB_PORT=3005
TRANSLATOR_BASIC_AUTH_ENABLED=true
TRANSLATOR_BASIC_AUTH_USERNAME=your-admin-user
TRANSLATOR_BASIC_AUTH_PASSWORD=your-strong-password
TRANSLATOR_CSRF_SECRET=your-high-entropy-secret
```

## Production-Like Hardening (Phases 2–5)

Since Phase 2, the canonical `docker-compose.yml` defaults to production-like runtime:

- `ASPNETCORE_ENVIRONMENT=Production` — Swagger gated by `Swagger__Enabled=false` (bound to `Swagger:Enabled`), HTTPS redirection active, ForwardedHeaders enabled.
- `BASIC_AUTH_ENABLED=true` — Translator admin requires credentials; defaults are rejected at startup.
- Rate limiting active on `/api/auth/*` (10 req/min) and `/api/reader/*` (60 req/min).
- Translator unknown errors return generic messages; internal details logged server-side.
- Translator admin mutations go through JSON API routes protected by Basic Auth and CSRF token checks.
- `AllowedHosts` always includes internal `api`; operators set only additional public backend hostnames.

Use `docker-compose.dev.yml` to restore development-friendly behavior for local iteration:
```bash
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.dev.yml up
```

## Stabilization Decisions and Honest Scope

### What v1 Stabilization Proves

- **Workspace discipline:** four separate implementation repos, parent `.planning/` local-only, Docker-first verification, and repo-specific status checks.
- **Deployment defaults:** API runs in `Production`, Swagger/ForwardedHeaders/RateLimiting are gated, translator fails closed with non-default credentials.
- **Auth surfaces:** JWT bearer auth on backend; Nuxt BFF sets HttpOnly `auth_token` with conditional `Secure` and `SameSite=Lax`; translator Basic Auth + CSRF for web forms.
- **Backend invariants:** EF migrations reconcile cleanly; collection add/move is idempotent/atomic; reading-progress upsert handles concurrent first writes; tags/categories protected by unique DB constraints.
- **Reader contracts:** `ChapterDetailDto` exposes `previousChapterId`/`nextChapterId`; catalog uses `CursorStringPagedResult<T>` with deterministic sort-value + ID tie-breakers.
- **Frontend integration:** `useApiFetch` is the single API layer; `useCatalogCursor.ts` owns catalog state; DTOs mirror backend contracts.
- **Translator operational reliability:** outbound timeouts/size limits, URL policy with private-URL escape hatch, safe `ExternalServiceError` mapping, Playwright sandbox opt-in, chunking wired into translation flow.
- **Test coverage:** backend xUnit regression suite, translator Vitest/Supertest suite (auth, CSRF, outbound, chunking), and Docker smoke checks for all services.

### What v1 Stabilization Does Not Prove

- **Refresh-token rotation** (v2: AUTH2-02). Access-token cookie is currently server-set and HttpOnly.
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
- Refresh-token rotation (v2).
