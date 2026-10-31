# Development Runbook

## Prerequisites (actual, from inspected config)

- Ruby 3.3.13 (`apps/api/.ruby-version`).
- PostgreSQL (`apps/api/config/database.yml`, `adapter: postgresql`).
- Node.js + npm for `apps/web` (Vite 8, TypeScript ~7.0).
- Redis (ADR-0006) — needed to enqueue and run jobs, not to boot the API
  or run the specs. Local: `redis-server` (default
  `redis://localhost:6379/0`, override with `REDIS_URL`). Worker:
  `cd apps/api && bin/jobs`.
- No `infrastructure/docker-compose.yml` exists yet — there is currently
  no one-command way to stand up Postgres and Redis locally.

## Standard feature workflow

0. Branch — at the start of every new phase, create a new branch from an
   up-to-date `main` (`git switch main && git pull && git switch -c
   feat/<short-kebab-name>`) before touching code. Never start a phase
   on `main` or on the previous phase's branch. Commit messages:
   `feat: <resumo do que foi implementado>`.
1. Requirement analysis — read the actual request/ticket.
2. Review relevant product docs (`docs/product/`).
3. Review relevant architecture docs (`docs/architecture/`, relevant ADRs
   in `docs/adr/`).
4. Inspect existing code for the affected area — do not assume prior
   session's described state is still accurate; re-check.
5. Identify affected domain(s) (`docs/domain/`).
6. Identify tenant-isolation and security impact
   (`docs/architecture/multi-tenancy.md`, `docs/architecture/security.md`).
7. Write an implementation plan; for architectural changes, propose an ADR
   update/addition first and get it reviewed before implementing.
8. Identify required tests before writing implementation code.
9. Implement, following existing patterns; no unrelated refactors.
10. Run automated validation (see `docs/runbooks/testing.md`) — actually
    run it, don't assume.
11. Update documentation affected by the change (including this harness's
    docs if architecture/domain shape changed).
12. Report: what changed, what was validated, what risks remain.

## Starting the backend (apps/api)

```
cd apps/api
bundle install
bin/rails db:prepare   # once a database.yml-reachable Postgres exists and
                        # migrations exist — neither is true yet for domain tables
bin/rails server
```

No `bin/dev` Procfile-based multi-process setup has been inspected beyond
the default `bin/dev` script already present — verify its contents before
relying on it for running Puma + any worker process together.

## Starting the frontend (apps/web)

```
cd apps/web
npm install
npm run dev
```

No `.env`/API base URL convention exists yet; once the API client layer is
built, document the convention here.

## Known gaps to close before "normal" day-to-day dev is smooth

CORS config, local Postgres (and possibly Redis) orchestration via
`infrastructure/`, Devise/Pundit install, first domain migration with UUID
PKs + RLS wired from the start.
