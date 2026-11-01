# LEASE INTELLIGENCE — ROOT ENGINEERING CONTEXT

This is the primary instruction file for the Lease Intelligence monorepo. It
is read on every Claude Code session opened at the repo root. Nested
CLAUDE.md files add detail for their subtree and never override this file's
safety rules.

- `apps/api/CLAUDE.md` — Rails API engineering context (detailed, authoritative for backend conventions).
- `.claude/rules/*.md` — path-specific, actionable rules (database, security, multi-tenancy, etc.).
- `.claude/agents/*.md` — specialized agents for architecture, Rails, security, AI/document pipeline, QA.
- `.claude/skills/*.md` — reusable workflows (feature implementation, migrations, security review, etc.).
- `docs/` — product, architecture, domain and ADR documentation. Treat `docs/adr/` as the source of truth for *why*; treat the code as the source of truth for *what is actually implemented*.

## 1. WHAT THIS PRODUCT IS

Lease Intelligence turns commercial lease agreements and related documents
into structured, traceable, actionable business intelligence for companies
that operate many leased properties (healthcare networks, gyms, restaurants,
retail chains, franchises, educational institutions). Initial market: Brazil.
Multi-tenant B2B SaaS, subscription-based.

AI (OCR + LLM) accelerates document interpretation, but a human must approve
any critical contractual fact before it is treated as ground truth. See
`docs/product/vision.md` and `docs/architecture/document-intelligence.md`.

## 2. REPOSITORY LAYOUT (ACTUAL, AS OF THIS INSPECTION)

```
apps/api/   Rails 8 API-only app (Ruby 3.3.13). Identity & Tenancy
            (users/tenants/memberships/invitations, RLS), session auth,
            Pundit, tenant context per request. Portfolio domain API
            (properties, counterparties) and Lease registration API
            (leases + lease_parties) and Document Management
            (contract_documents + immutable document_versions, upload,
            5-minute download links — ADR-0015) and text extraction
            (native PDF text + local Tesseract OCR per page, Sidekiq job,
            ADR-0016) and AI field extraction (Claude or a local
            Ollama model via the Llm interface, per-organization
            consent off by default, evidence verified against the
            stored text, unreviewed candidates only — ADR-0017/0018).
            No review or conditions yet.
apps/web/   Vite + React 19 + TypeScript SPA. Login -> organization
            picker -> routed workspace (React Router, ADR-0014) with
            properties, counterparties and leases screens; services/
            API client; hand-rolled useApiQuery (no data library).
.github/    CI (workflows/ci.yml) + dependabot, at the repo root.
docs/       product / architecture / domain / adr / runbooks (scaffolded,
            now populated by this harness).
infrastructure/   docker-compose.yml for local Postgres 16 + Redis (dev
                  only; no IaC yet).
scripts/          empty — no validation/dev scripts yet.
.claude/    agents, rules, skills (scaffolded, now populated).
```

Do not assume anything beyond this exists. If a document describes a
"planned" architecture, it is NOT implemented until the code says otherwise.

## 3. KNOWN INCONSISTENCIES TO RESOLVE BEFORE BUILDING FEATURES

These were found during harness setup and are **not yet fixed** — do not
build on top of them silently; surface them when relevant:

1. **Background processing: resolved — Sidekiq + Redis (ADR-0006).**
   Solid Queue was removed; `config.active_job.queue_adapter = :sidekiq`
   (`:test` in specs), worker via `apps/api/bin/jobs`. Jobs that touch
   tenant data use `ApplicationJob#within_tenant(tenant_id)`, which fails
   loudly without a valid active tenant. `solid_cache`/`solid_cable`
   remain (cache/cable, not jobs). Still open: no Sidekiq Web UI, no
   periodic jobs (Sidekiq OSS has no cron), Redis is not in CI (not
   needed — specs use the test adapter).
2. **CORS: resolved by design, not by `rack-cors` (ADR-0013).** The SPA
   is served same-origin (Vite proxies `/api` in dev, a reverse proxy in
   prod), so the session cookie is first-party and no CORS is needed. The
   Vite proxy is in `apps/web/vite.config.ts`; the production reverse
   proxy does not exist yet. `config/initializers/cors.rb` stays
   the unused template; do not add `rack-cors` without revisiting ADR-0013.
3. **Auth + tenant context are implemented (API only, ADR-0013).** Devise
   session in an httpOnly cookie (`/api/v1/session`, `/api/v1/me`),
   Pundit installed (`ApplicationPolicy` deny-by-default,
   `verify_authorized` on every action, `AuthorizationContext(user,
   membership)`), `TenantScoped` concern resolving `X-Tenant-Id` against
   active memberships, Rack::Attack on sign-in. The SPA login /
   organization picker is built. Not built: sign-up/org creation,
   invitation acceptance, password reset.
4. **Local orchestration: dev only.** `infrastructure/docker-compose.yml`
   runs Postgres 16 (port 5434, RLS-safe app role) and Redis; Ollama runs
   natively (GPU). `apps/api/Dockerfile` is production-only
   (Kamal-oriented); there is no IaC.
5. **RLS and the Identity & Tenancy schema are now implemented**
   (`tenants`, `users`, `memberships`, `invitations` — see
   `docs/domain/identity.md`, `docs/adr/0003-postgresql-rls.md`), and so
   is Portfolio (`properties`, `counterparties` — `docs/domain/portfolio.md`)
   and the lease registration (`leases`, `lease_parties` —
   `docs/domain/leases.md`; no amendments/conditions yet), Document
   Management (`contract_documents`, `document_versions` —
   `docs/domain/documents.md`, ADR-0015), text extraction
   (`document_text_extractions`, `document_text_pages` — ADR-0016) and AI
   field extraction (`extraction_runs`, `extracted_fields`,
   `evidence_references` — `docs/domain/contract-intelligence.md`,
   ADR-0017).
   Every other module (Contract Review, Obligations, Audit &
   Security) is still
   unimplemented and must repeat the RLS checklist in
   `docs/runbooks/database.md` independently — nothing is automatic. Note
   `config.active_record.schema_format` is now `:sql`
   (`db/structure.sql`), required for RLS to survive `db:test:prepare` —
   see the runbook.
6. **Git topology: single monorepo at the root.** The nested
   `apps/api/.git` no longer exists; commit everything from the root
   repository, one branch per phase (§5).
7. **Rails/json: resolved.** `apps/api` is on Rails `~> 8.1.4` with
   `json ~> 3.1` (the old `~> 2.16` pin existed only because json 3.x
   broke ActiveSupport 8.0's encoder). The Rails 8.0 end-of-life entry was
   removed from `config/brakeman.ignore`, which is now empty — any
   Brakeman warning fails CI again.

## 4. NON-NEGOTIABLE SAFETY RULES

Never, under any circumstance, without explicit human authorization and an
audit trail:

- Implement cross-tenant data access, including "admin" bypasses.
- Disable or weaken PostgreSQL RLS to make a test or migration pass.
- Trust a `tenant_id` supplied by the frontend/API input instead of deriving
  it from authenticated membership context.
- Put business rules in controllers.
- Use floating-point types for money. Use `decimal` with explicit currency.
- Overwrite or mutate an original uploaded contract document.
- Publish an AI extraction as an approved contractual fact without the
  required human review step.
- Add a dependency without stating its architectural justification.
- Perform refactoring unrelated to the task at hand.
- Claim tests passed, or a feature works, without having actually run them.

## 4A. SESSION BOUNDARY RULE

When a task is finished (completion report delivered), end the session
there — the next task starts in a **new** Claude Code session rather than
continuing to accumulate unrelated work in the same conversation. This
keeps each session's context scoped to one task and keeps this harness
(not conversational memory) as the durable source of project state.
Practically: state clearly that the task is complete and that a new
session should be started for the next task, instead of drifting into the
next task in the same thread.

## 5. HOW TO WORK ON A FEATURE

Follow the standard workflow in `docs/runbooks/development.md`. In short:
requirement analysis → read product/architecture docs → inspect existing
code → identify domain + tenant/security impact → plan → identify tests →
(get approval for architectural changes) → implement → validate → update
docs → report. Use the `implement-feature` skill as the entry point for
non-trivial feature work.

**Branch per phase (mandatory):** every time a new development phase
starts (e.g. authentication, documents upload, OCR pipeline, frontend
shell), create a new branch for it from an up-to-date `main` *before*
writing any code — never start a new phase on `main` or on the previous
phase's branch. Name it `feat/<short-kebab-name>` (`fix/<name>` for a
bug fix). Commit messages: `feat: <resumo do que foi implementado>`
(`fix: ...` for fixes) — one short summary line of what was implemented.
Do not commit or push unless the user asks.

## 6. QUALITY GATES (see docs/runbooks/testing.md for exact commands)

All gates run in `.github/workflows/ci.yml` (repo root) on every PR and
push to `main`: backend RSpec (as a non-superuser, no-BYPASSRLS role),
RuboCop (Omakase), Brakeman; frontend oxlint + `tsc -b` + Vite build.
The frontend has no test runner yet (a dependency decision still open).
Do not claim a gate "passes" without running the exact command from the
runbook.

## 7. PRIMARY ENGINEERING PRINCIPLE

The reliability of contractual information matters more than how much the
AI can extract. Build a maintainable, secure, auditable, evidence-first
system. Prefer explicit engineering decisions over clever abstractions.
