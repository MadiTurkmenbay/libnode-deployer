# AI_INSTRUCTIONS

## Workspace Guardrails

- Read `/home/qustust/projects/libnodeProject/AGENTS.md` before this file.
- This repo is the Docker Compose orchestration and verification repository for LibNode.
- Do not place backend, frontend, translator application logic, runtime hardening fixes, EF migrations, Prisma schema changes, or UI changes in this repo.
- Before editing or committing on user request, run `git status --short`, `git diff`, and `git diff --staged` from `libnode-deployer/`.
- Never read, print, commit, or summarize real `.env`, `.env.local`, `.env.verify`, data mounts, Playwright storage state, browser profiles, logs, or expanded Compose config.
- Use `docker compose config --quiet` for shared Compose validation. Do not paste full `docker compose config` output.
- Verification examples must use placeholders only. Use `.env.verify.example` for committed verify inputs and `.env.verify` only as ignored local runtime input.
- Keep Phase 1 changes to workspace guidance, verification scaffolding, ignore hygiene, and docs. Production-like runtime hardening belongs to later plans.
