---
applies_to: apps/api/**
---

# Multi-Tenancy Rules

See `docs/architecture/multi-tenancy.md` for the full design and
ADR-0002/ADR-0003 for the rationale. Operational rules:

- Resolve the current tenant from authenticated membership data
  server-side. Never trust a `tenant_id` from a request param, header, or
  frontend-controlled state as the source of truth for which tenant an
  operation runs against.
- PostgreSQL RLS is the enforced isolation boundary, not
  `default_scope`/application-level scoping. Application-level scoping is
  a secondary, defense-in-depth layer, never the sole control.
- Set tenant context per-transaction (`SET LOCAL`), never per-connection —
  pooled connections are reused across requests, and a tenant setting
  that survives past its request is a cross-tenant leak waiting to
  happen. The middleware/concern that sets this must also guarantee it's
  cleared/scoped correctly; this needs its own regression test.
- Background jobs do not inherit request-local tenant context. Every job
  must receive what it needs to explicitly re-establish tenant context
  and must fail loudly (not silently no-op or default to some fallback
  tenant) if it cannot.
- Cross-tenant relationships between tenant-owned records must be
  prevented at the database level (composite FKs / check constraints),
  not just assumed correct by application code.
- Every new tenant-scoped feature requires the three-layer isolation test
  (policy deny test, request-level cross-tenant test, raw-SQL RLS test)
  described in `docs/runbooks/testing.md` before it's considered done.
- Any cross-tenant access path (e.g. an internal admin/support tool) must
  be explicit, authorized, and audited — never a silent bypass, and never
  introduced without `security-engineer` review (root `CLAUDE.md` §9).
