---
name: tenant-isolation-review
description: Use whenever a new tenant-owned table, model, policy, or endpoint is created or changed on Lease Intelligence. Verifies the full tenant isolation chain (RLS, tenant context resolution, connection pool safety, background job isolation) and the required three-layer test coverage.
---

# Tenant Isolation Review

## Required context

`docs/architecture/multi-tenancy.md`, ADR-0002, ADR-0003,
`.claude/rules/multi-tenancy.md`, `docs/runbooks/testing.md` (for the
three-layer test pattern), `docs/runbooks/database.md` (for the RLS
migration checklist).

## Workflow

1. **Table level** — confirm the table has `tenant_id`, RLS enabled and
   forced, and a correct isolation policy, created in the same migration
   as the table (not a follow-up).
2. **Query level** — grep the model/service/controller code for any raw
   SQL, `.unscoped`, or ActiveRecord query that could bypass tenant
   scoping; confirm RLS would still catch it even if application-level
   scoping were accidentally omitted.
3. **Context resolution** — confirm the tenant context used for a
   request/job comes from authenticated membership data, never from a
   client-supplied parameter/header taken at face value.
4. **Connection pool safety** — confirm tenant context is set `SET LOCAL`
   per-transaction, not per-connection, and is not left set on a
   connection returned to the pool.
5. **Background job isolation** — confirm any job touching this table
   explicitly re-establishes tenant context and fails loudly without one.
6. **Cross-tenant relationship integrity** — if this table references
   another tenant-owned table, confirm a composite FK / check constraint
   prevents linking rows across tenants.
7. **Test coverage** — confirm all three layers exist: a policy spec
   proving cross-tenant deny, a request spec proving a cross-tenant
   request is rejected (403/404, no data leak), and a raw-SQL RLS spec
   that bypasses application authorization entirely and proves the
   database refuses the cross-tenant row.

## Output

A pass/fail per checklist item above, with the specific file/line
evidence for each, and — for any failing item — the concrete cross-tenant
scenario it would allow if shipped as-is.
