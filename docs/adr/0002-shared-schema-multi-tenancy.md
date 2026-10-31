# ADR-0002: Shared-Schema Multi-Tenancy

## Context

Lease Intelligence is multi-tenant B2B SaaS. Tenant data (properties,
leases, documents, extracted facts) must never be visible across tenants.

## Problem

Choose a multi-tenancy data isolation strategy that balances operational
simplicity, cost, and the strength of the isolation guarantee.

## Decision

Use a shared database, shared schema, with a `tenant_id` column on every
tenant-owned table, and PostgreSQL Row-Level Security (ADR-0003) as the
enforced isolation boundary.

## Alternatives considered

- **Database-per-tenant** — strongest isolation, but operationally
  expensive at scale (migrations fan out across N databases, connection
  management complexity) and overkill for the current customer scale
  target. Reconsider if a specific enterprise customer requires physical
  data separation contractually.
- **Schema-per-tenant** — middle ground, still multiplies migration
  operations per tenant and complicates connection pooling in Rails;
  rejected for the same operational reasons, with less isolation benefit
  than database-per-tenant to justify the cost.
- **Shared schema with only `default_scope`/application-level filtering,
  no RLS** — rejected: a single missed `.unscoped` or raw SQL query would
  silently leak cross-tenant data with no database-level backstop. Not
  acceptable given the product's "strict tenant isolation" principle.

## Consequences

- Positive: single schema to migrate, simplest operational model, lowest
  infrastructure cost, standard Rails connection pooling works unmodified.
- Negative: isolation now depends entirely on disciplined `tenant_id`
  usage plus RLS being correctly configured on every tenant-owned table —
  a single table created without RLS enabled is a real leak vector that
  must be caught by process (migration review checklist, tests) not
  assumed away.
- Composite foreign keys / check constraints (see
  `docs/architecture/multi-tenancy.md`) become necessary extra work to
  prevent cross-tenant row linkage.

## Security implications

This is the central security decision of the product. RLS (ADR-0003) is
the non-negotiable complement to this choice — shared schema without RLS
would be an unacceptable risk. Every new tenant-owned table's migration
must enable RLS and add the tenant isolation policy as part of the same
change, never as a follow-up.

## Implementation status

**Implemented for the Identity & Tenancy module.** `tenants`,
`memberships`, `invitations` exist with `tenant_id`/RLS as designed
(`memberships` and `invitations` are tenant-owned; `tenants` and `users`
are deliberately not, see `docs/domain/identity.md`). There is still no
request-level tenant context middleware (`TenantContext`, the
transaction-scoped mechanism, exists and is tested at the service/model
layer — see `docs/adr/0003-postgresql-rls.md` — but no controller wires
it to an authenticated request yet, since no controllers exist in this
data-layer phase). Not yet extended to Portfolio, Leases, Documents, or
any later module.
