# Development Runbook

## Prerequisites (actual, from inspected config)

- Ruby 3.3.13 (`apps/api/.ruby-version`).
- PostgreSQL (`apps/api/config/database.yml`, `adapter: postgresql`).
- Node.js + npm for `apps/web` (Vite 8, TypeScript ~7.0).
- Redis (ADR-0006) — needed to enqueue and run jobs, not to boot the API
  or run the specs. Local: `redis-server` (default
  `redis://localhost:6379/0`, override with `REDIS_URL`). Worker:
  `cd apps/api && bin/jobs`.
- Or both at once, containerized: `docker compose -f
  infrastructure/docker-compose.yml up -d` — PostgreSQL 16 (CI's version)
  on host port **5434** (so it coexists with host clusters on 5432/5433)
  with the `lease_intelligence` role created `NOSUPERUSER NOBYPASSRLS
  CREATEDB` on first start, and Redis on 6379. Point the app at it with
  `LEASE_INTELLIGENCE_DATABASE_PORT=5434`, then `bin/rails db:prepare`.
  The full suite was verified green against it.

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

System packages for text extraction (ADR-0016) — the Sidekiq worker runs
OCR locally:

```
sudo apt-get install -y tesseract-ocr tesseract-ocr-por poppler-utils
```

Without them, digital PDFs still get their native text, scanned pages and
images end as `failed` / `ocr_unavailable`, and the real-adapter specs are
skipped locally (never in CI). Text extraction runs in the worker
(`bin/jobs`, needs Redis on `localhost:6379`); without it, uploads stay
"Na fila" in the SPA.

AI field extraction (ADR-0017, ADR-0018) needs two things:

1. **A provider for the deployment**, in the environment of the web and
   worker processes:
   - local, free, nothing leaves the host — `LLM_PROVIDER=ollama`, with
     Ollama running natively (`ollama pull qwen2.5:7b`; `OLLAMA_URL`,
     `OLLAMA_MODEL`, `OLLAMA_NUM_CTX` override the defaults). On an 8 GB
     GPU, `OLLAMA_NUM_CTX=16384` keeps the model entirely on the GPU
     (measured: 59 s instead of 177 s for a 2-page contract) at the cost
     of a ~24 000-character input limit (about 8–10 pages); the default
     32768 reads ~74 000 characters but spills to the CPU. Never use a
     `:cloud` model — the adapter refuses them;
   - Claude — `LLM_PROVIDER=anthropic` (or unset) plus `ANTHROPIC_API_KEY`
     (or `anthropic: { api_key: ... }` in credentials). The text of every
     contract is sent to Anthropic: read the LGPD notes in ADR-0017 first.
2. **The organization's consent**: off by default; an owner/admin turns it
   on in the SPA's "Configurações". Off, no run is requested after a text
   extraction and the documents table says "IA desligada".

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

CORS config, Devise/Pundit install, first domain migration with UUID
PKs + RLS wired from the start. (Local Postgres/Redis orchestration now
exists: `infrastructure/docker-compose.yml`.)
