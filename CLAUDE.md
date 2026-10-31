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
apps/api/   Rails 8 API-only app (Ruby 3.3.4). Skeleton only: no domain
            models, no migrations, no initialized Devise/Pundit, no RLS.
apps/web/   Vite + React 19 + TypeScript SPA. Vanilla template, no routing,
            no API client layer, no feature structure yet.
docs/       product / architecture / domain / adr / runbooks (scaffolded,
            now populated by this harness).
infrastructure/   empty — no docker-compose, no IaC yet.
scripts/          empty — no validation/dev scripts yet.
.claude/    agents, rules, skills (scaffolded, now populated).
```

Do not assume anything beyond this exists. If a document describes a
"planned" architecture, it is NOT implemented until the code says otherwise.

## 3. KNOWN INCONSISTENCIES TO RESOLVE BEFORE BUILDING FEATURES

These were found during harness setup and are **not yet fixed** — do not
build on top of them silently; surface them when relevant:

1. **Background processing is ambiguous.** `Gemfile` includes both the
   Rails 8 default (`solid_queue`, `solid_cache`, `solid_cable`, DB-backed,
   already wired as `config.active_job.queue_adapter` in
   `config/environments/production.rb`) **and** `sidekiq` (~> 8.1, with
   `redis-client` as a transitive dependency) — but Sidekiq is not wired as
   the ActiveJob adapter anywhere, and there is no Redis service, no
   `config/sidekiq.yml`, no Sidekiq initializer. The product instructions
   (`apps/api/CLAUDE.md` §4) mandate Sidekiq + Redis for background
   processing. **Pick one and remove the other** before writing jobs — see
   ADR-006.
2. **CORS: resolved by design, not by `rack-cors` (ADR-0013).** The SPA
   is served same-origin (Vite proxies `/api` in dev, a reverse proxy in
   prod), so the session cookie is first-party and no CORS is needed. The
   Vite proxy itself is **not configured yet** (frontend phase) — until
   then the SPA cannot call the API. `config/initializers/cors.rb` stays
   the unused template; do not add `rack-cors` without revisiting ADR-0013.
3. **Auth + tenant context are implemented (API only, ADR-0013).** Devise
   session in an httpOnly cookie (`/api/v1/session`, `/api/v1/me`),
   Pundit installed (`ApplicationPolicy` deny-by-default,
   `verify_authorized` on every action, `AuthorizationContext(user,
   membership)`), `TenantScoped` concern resolving `X-Tenant-Id` against
   active memberships, Rack::Attack on sign-in. Not built: sign-up/org
   creation, invitation acceptance, password reset, the SPA login screen.
4. **No local orchestration.** `infrastructure/` is empty — no
   `docker-compose.yml` for Postgres/Redis/local dev. `apps/api/Dockerfile`
   is production-only (Kamal-oriented).
5. **RLS and the Identity & Tenancy schema are now implemented**
   (`tenants`, `users`, `memberships`, `invitations` — see
   `docs/domain/identity.md`, `docs/adr/0003-postgresql-rls.md`). Every
   other module (Portfolio, Lease Management, Document Management,
   Contract Intelligence, Obligations, Audit & Security) is still
   unimplemented and must repeat the RLS checklist in
   `docs/runbooks/database.md` independently — nothing is automatic. Note
   `config.active_record.schema_format` is now `:sql`
   (`db/structure.sql`), required for RLS to survive `db:test:prepare` —
   see the runbook.
6. **Git topology: single monorepo at the root.** The nested
   `apps/api/.git` no longer exists; commit everything from the root
   repository, one branch per phase (§5).
7. **`json` gem pinned to `~> 2.16`** in `apps/api/Gemfile`: json 3.x
   breaks ActiveSupport 8.0's encoder (`unknown keyword: quirks_mode` on
   every `render json:`). Remove the pin only together with a Rails
   upgrade that fixes it. Rails 8.0 support ends 2026-11-07 (Brakeman
   EOLRails warning) — plan the upgrade.

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
phase's branch. Name it `phase/<short-kebab-name>` (or `feat/`, `fix/`,
`chore/` for work smaller than a phase). Confirm the repository topology
(§3, item 6) first if it is still unresolved. Do not commit or push
unless the user asks.

## 6. QUALITY GATES (see docs/runbooks/testing.md for exact commands)

Backend: RSpec, RuboCop (Omakase), Brakeman — all three are already wired in
`apps/api/.github/workflows/ci.yml`. Frontend: `tsc -b` (typecheck), `oxlint`
(lint) — wired in `apps/web/package.json`. There are currently zero
application-level tests on either side; the CI pipeline runs against an
empty app. Do not claim a gate "passes" without running the exact command
from the runbook.

## 7. PRIMARY ENGINEERING PRINCIPLE

The reliability of contractual information matters more than how much the
AI can extract. Build a maintainable, secure, auditable, evidence-first
system. Prefer explicit engineering decisions over clever abstractions.
