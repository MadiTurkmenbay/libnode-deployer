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

## Production-Like Hardening (Phase 2)

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

## What Phase 2 Does Not Prove

Phase 2 hardening covers deployment defaults, auth surfaces, and error safety. It does not prove:
- EF/Prisma migration correctness (Phase 3).
- Collection idempotency or reading-progress concurrency (Phase 3).
- Reader neighbor contract or catalog cursor pagination (Phase 4).
- Translator outbound timeout/size limits or chunked translation (Phase 5).
- Server-set HttpOnly session cookies (v2).
