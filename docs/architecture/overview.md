# Architecture Overview

Status: planned architecture. Current implementation is a bare Rails 8 API
skeleton and a vanilla Vite/React SPA — see root `CLAUDE.md` §3 for the gap
list. This document describes the target shape; do not assume any of it
exists until it's been built and tested.

## Shape

Modular monolith (ADR-001), not microservices, not one Rails Engine per
domain. Two deployable units:

- `apps/api` — Rails 8, API-only, REST, PostgreSQL, background jobs.
- `apps/web` — React + TypeScript SPA, Vite build, talks to `apps/api` over
  HTTP/JSON.

```
[React SPA (apps/web)]
        | HTTPS / JSON (REST, /api/v1)
        v
[Rails API (apps/api)] --- Pundit authorization, tenant context middleware
        |         \
        |          \--> [PostgreSQL: shared schema + RLS] (ADR-002, ADR-003)
        |
        \--> [Background jobs] --(TBD: Sidekiq+Redis or Solid Queue — ADR-006)
                    |
                    \--> [OCR provider] (ADR-008, abstracted)
                    \--> [LLM provider] (ADR-009, abstracted)
                    \--> [Private object storage] (ADR-007, Active Storage)
```

## Domain boundaries (suggested; not yet implemented as code modules)

- **Identity** — User, Tenant, Membership, authentication.
- **Tenancy** — tenant context resolution, RLS enforcement plumbing.
- **Portfolio** — Property, Counterparty.
- **Leases** — Lease, Amendment, ContractualCondition.
- **Documents** — ContractDocument, DocumentVersion, private storage.
- **ContractIntelligence** — ExtractionRun, ExtractedField,
  EvidenceReference, OCR/LLM provider adapters.
- **ContractReview** — ReviewDecision, approval workflow.
- **Obligations** — Obligation, CalendarEvent, generation rules.
- **Notifications** — delivery of obligation/deadline alerts.
- **Audit** — AuditEvent recording.
- **Integrations** — external provider adapters (OCR, LLM, storage), kept
  behind interfaces so no domain code depends on a specific vendor SDK.

Domains should map to `app/domains/<name>/` or a similarly explicit
namespace once code is written (decide and document in an ADR update when
the first domain is implemented) — do not scatter domain logic across
generic `app/models` and `app/services` with no namespacing.

## Backend architecture

Controllers are thin: parse params, call a service/query object, render a
serializer. Business rules live in service objects and domain models, never
in controllers or in callbacks that hide control flow. See
`docs/architecture/backend.md` and `.claude/rules/backend.md`.

## Frontend architecture

React + TypeScript SPA with a clear separation of pages, features,
components, hooks, an API client layer, and types. See
`docs/architecture/frontend.md` and `.claude/rules/frontend.md`.

## Database strategy

Single shared PostgreSQL database, shared schema, tenant_id column on every
tenant-owned table, PostgreSQL Row-Level Security as the enforced boundary
(not just an application-level `default_scope`). UUID primary keys. See
`docs/architecture/multi-tenancy.md`.

## Background processing

Must be asynchronous, idempotent, and tenant-context-aware (a job must
re-establish tenant context explicitly — it cannot inherit request-local
state). The adapter (Sidekiq+Redis vs. Solid Queue) is currently
undecided in practice — see the inconsistency note in root `CLAUDE.md` and
ADR-006.

## External integrations

OCR and LLM providers are accessed through an internal abstraction
(interface + adapter per vendor) so the vendor can be swapped without
touching domain code. See ADR-008 and ADR-009.
