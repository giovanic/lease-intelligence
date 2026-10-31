# Multi-Tenancy Architecture

Status: implemented for Identity & Tenancy (`Tenant`, `User`,
`Membership`, `Invitation`, RLS policies, and the transaction-scoped
`TenantContext` service — see `apps/api/app/services/tenant_context.rb`
and `docs/domain/identity.md`). There is still no HTTP-request-level
middleware wiring `TenantContext` to an authenticated controller action
(no controllers exist in this data-layer phase), and no other module's
tables exist yet — each must independently follow this design. See
ADR-0002 and ADR-0003 (including its addendum on the schema-format
requirement and the self-visibility bootstrap policy).

## Tenant model

Shared database, shared schema. Every tenant-owned table carries a
`tenant_id` (UUID, foreign key to `tenants`). A `Tenant` is the billable
organization/customer account.

## User and membership model

- `User` is a global identity (one row per person), independent of any
  tenant. A user authenticates once and may hold access to multiple
  tenants.
- `Membership` joins `User` and `Tenant`, carrying role/permission data for
  that specific tenant. All authorization decisions within a tenant context
  are derived from the current user's `Membership` for that tenant — never
  from a global "is admin" flag alone.

## Tenant context resolution

A request must resolve "which tenant is this operating as" from trustworthy
server-side state (the authenticated session/token plus the user's
memberships), never from a client-supplied `tenant_id` parameter or header
taken at face value. The resolved tenant must then be set as the
transaction-local context for the duration of the request (see RLS below)
and torn down afterward — it must not leak into the next request served by
a pooled connection.

## PostgreSQL Row-Level Security (RLS)

RLS policies on every tenant-owned table restrict visible/writable rows to
the current session's tenant context (typically via
`current_setting('app.current_tenant_id')` set per-transaction). The Rails
database role used by the application **must not** be a superuser and must
not have `BYPASSRLS`. RLS is the enforced boundary; Rails-level scoping
(`default_scope`, explicit `where(tenant_id: ...)`) is a secondary,
defense-in-depth layer — it is not sufficient on its own and must never be
treated as the primary control.

## Composite foreign keys

Where a child table references another tenant-owned table, the foreign key
relationship should be validated to also agree on `tenant_id` (e.g. via a
composite foreign key or an equivalent check constraint), so it is
impossible at the database level to create a row that links two different
tenants' data together.

## Connection pool safety

Because Rails reuses pooled PostgreSQL connections across requests, any
session-local tenant setting (`SET app.current_tenant_id`) must be
set per-transaction (e.g. `SET LOCAL` inside the request's transaction) and
must never persist on a connection returned to the pool. A middleware/
concern establishes and clears this per request; this must be covered by a
regression test that proves no leakage across simulated requests on the
same connection.

## Background job isolation

A job does not inherit the HTTP request's tenant context. Every job must
receive and explicitly (re-)establish the tenant context it needs before
touching tenant-owned data, and must fail loudly if it cannot establish
one — never silently operate tenant-less or default to some "first tenant."

## Cross-tenant security tests

Every tenant-scoped feature requires an automated test proving both: (a)
same-tenant access works, and (b) cross-tenant access is denied — at the
policy layer, the request layer, and ideally with a raw-SQL-level RLS test
that does not go through application authorization at all (to prove the
database itself refuses the row, independent of app-layer bugs). See
`.claude/rules/multi-tenancy.md` and the `tenant-isolation-review` skill.
