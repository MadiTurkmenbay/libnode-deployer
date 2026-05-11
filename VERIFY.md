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

## What Phase 1 Does Not Prove

Phase 1 verification checks Compose syntax, placeholder wiring, and disposable dependency wiring. It does not prove backend production runtime hardening, translator auth/CSRF/rate limits, EF/Prisma migration correctness, reader contracts, catalog pagination, collection/progress invariants, or translator chunking behavior.
