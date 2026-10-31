---
name: create-database-migration
description: Use when creating or modifying an ActiveRecord migration in apps/api — especially for a new tenant-owned table, which has mandatory RLS/tenant_id/UUID requirements. Walks the checklist and required validation before the migration is considered safe to run.
---

# Create Database Migration

## Required context

`docs/runbooks/database.md` (the authoritative checklist), ADR-0002
(shared-schema multi-tenancy), ADR-0003 (RLS), ADR-0004 (UUID PKs),
`.claude/rules/database.md`. Inspect existing migrations (if any) for the
established tenant-isolation pattern before inventing a new one.

## Workflow

1. Determine: is the new/changed table tenant-owned (belongs to a
   specific tenant) or global (e.g. `tenants` itself, or genuinely
   cross-tenant reference data)? Default assumption is tenant-owned
   unless proven otherwise.
2. Use UUID primary keys (`id: :uuid`, or the project-wide generator
   default if already configured).
3. For a tenant-owned table, in the **same migration**:
   - add an indexed `tenant_id` column (UUID, FK to `tenants`)
   - `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
   - `ALTER TABLE ... FORCE ROW LEVEL SECURITY;`
   - create the tenant isolation RLS policy
4. Use `decimal` with explicit precision/scale for any monetary column,
   paired with an explicit currency code column. Never `float`.
5. Use `date` vs `datetime` correctly per the column's actual semantics —
   do not default to `datetime`.
6. Add foreign keys, check constraints, and partial unique indexes for
   invariants that must hold at the database level, not just in model
   validations.
7. Where a child table references another tenant-owned table, add a
   composite foreign key / check constraint ensuring both rows share the
   same `tenant_id`.
8. Confirm (do not assume) the application's Postgres role has no
   `BYPASSRLS` and is not a superuser.

## Validation

Run `bin/rails db:migrate` and `bin/rails db:rollback` (to confirm the
migration reverses cleanly) in a local/test environment. Write the
raw-SQL-level RLS test described in `docs/runbooks/testing.md` proving
Postgres itself refuses a cross-tenant row read/write, independent of
application code.

## Output

A migration file following the checklist above, plus the RLS test. Never
report a migration as safe without having actually run it and the
associated RLS test.
