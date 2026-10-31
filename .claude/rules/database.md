---
applies_to: apps/api/db/**, apps/api/app/models/**
---

# Database Rules

- UUID primary keys on every table (ADR-0004). Configure this as a
  project-wide generator default rather than setting `id: :uuid` ad hoc
  per migration.
- Every tenant-owned table: `tenant_id` column (UUID, FK to `tenants`,
  indexed), RLS enabled (`ENABLE ROW LEVEL SECURITY`) and forced
  (`FORCE ROW LEVEL SECURITY`), and the tenant isolation policy — all in
  the **same migration** that creates the table. See the full checklist
  in `docs/runbooks/database.md`.
- Composite foreign keys / check constraints where a child table
  references another tenant-owned table, so the database itself rejects
  a row that would link two different tenants' data (ADR-0002).
- Money: `decimal` with explicit precision/scale. Never `float`/`real`
  for anything monetary. Always pair with an explicit currency code
  column.
- Dates: `date` for calendar-only semantics, `datetime`/`timestamp` only
  when time-of-day matters. Do not default to `datetime` out of habit.
- Add database constraints for invariants that matter (uniqueness,
  referential integrity, valid ranges) — do not rely on model validations
  alone; a direct SQL write or a bug in validation logic must still be
  caught by the database.
- Index foreign keys and any column used in an RLS policy predicate
  (typically `tenant_id`).
- Never write a migration that disables, drops, or weakens an existing
  RLS policy to resolve a failing test or a blocked migration — fix the
  underlying tenant-context or query issue instead (root `CLAUDE.md` §4).
- The application's Postgres role must never be a superuser and must
  never have `BYPASSRLS` — if a migration or setup script grants this,
  that is a bug to fix, not a known limitation to work around.
