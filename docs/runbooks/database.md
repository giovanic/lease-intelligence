# Database Runbook

## Current state

Identity & Tenancy is implemented: `tenants`, `users`, `invitations`,
`memberships` (`apps/api/db/migrate/202610311332*`), plus the
`app_current_tenant_id()`/`app_current_user_id()` SQL functions RLS
policies depend on. Schema is dumped as `db/structure.sql` (**not**
`db/schema.rb` — see the schema-format gotcha below), alongside the
Rails-8-generated `db/cable_schema.rb`/`cache_schema.rb`/`queue_schema.rb`
(Solid Cable/Cache/Queue support schemas, unrelated to the primary
database). Portfolio is implemented too: `properties` and
`counterparties` (`apps/api/db/migrate/20261031150000*`/`150001*`), each
with RLS + a unique `(id, tenant_id)` index. Leases use them:
`leases` (`20261031180000`) and `lease_parties` (`20261031180001`) point
at properties/counterparties/leases through composite foreign keys on
`(id, tenant_id)` (`fk_leases_property_same_tenant`,
`fk_lease_parties_*_same_tenant`) — the reference pattern for any child
of a tenant-owned table. Documents (`contract_documents`,
`document_versions`) follow the same pattern, and `document_versions` adds
an immutability trigger (rejects UPDATE/DELETE) — `TRUNCATE` is not
blocked by it. Text extraction (`document_text_extractions`,
`document_text_pages`, ADR-0016) follows it too, with the same kind of
immutability trigger on `document_text_pages`. No other module's tables
exist yet.

`db/structure.sql` must load on the CI's PostgreSQL 16: a dump made by a
newer local server/`pg_dump` may add `SET transaction_timeout = 0;`
(PG 17+), which PG 16 rejects — drop that line before committing.

Local Postgres setup actually in place: a dedicated role
`lease_intelligence` (non-superuser, no `BYPASSRLS`, **does** have
`CREATEDB` — see note below) owns `lease_intelligence_development` and
`lease_intelligence_test`, connected over TCP with a password from
`config/database.yml` (`LEASE_INTELLIGENCE_DATABASE_PASSWORD` env var,
defaults to a local-only dev value). There is still no
`infrastructure/docker-compose.yml` — this setup was done directly
against the machine's existing Postgres install, not containerized.

### Schema-format gotcha (read before touching any migration with `execute`)

`config.active_record.schema_format = :sql` is set in
`config/application.rb`. This is **required**, not a style preference:
the default Ruby format (`db/schema.rb`) cannot represent RLS policies,
`FORCE ROW LEVEL SECURITY`, or custom SQL functions — anything added via
`execute "..."` in a migration. Rebuilding a database from `schema.rb`
(as `db:test:prepare` does) would silently produce a copy with **no RLS
at all**. This was caught empirically — see
`docs/adr/0003-postgresql-rls.md` addendum. Never switch this back to
`:ruby` without re-verifying RLS survives a fresh `db:test:prepare`.

`pg_dump`/`psql` version must match (or be compatible with) the running
server. This machine has multiple PostgreSQL versions installed and the
default `pg_dump`/`psql` on `PATH` may resolve to a mismatched version
(observed: a v17 client emitting a v17-only GUC into the dump, which a
v16 server then rejected on load). If `db:migrate`/`db:test:prepare`
errors with `unrecognized configuration parameter`, prefix `PATH` with
the correct versioned `bin/` directory, e.g.:
`PATH="/usr/lib/postgresql/16/bin:$PATH" bin/rails db:test:prepare`.

### Why the app role has `CREATEDB`

`ActiveRecord::Migration.maintain_test_schema!`/`db:test:prepare` purge
and recreate the test database using whatever role is configured for
that environment — this requires `CREATEDB`. Granting `CREATEDB` to
`lease_intelligence` does **not** weaken the RLS guarantee: it is an
orthogonal privilege dimension from `SUPERUSER`/`BYPASSRLS`, which remain
unset (verify with
`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname =
'lease_intelligence';` — must be `f, f`). The hard rule in
`.claude/rules/database.md` is specifically about superuser/BYPASSRLS,
not database-admin privileges.

## Conventions to apply from the very first migration

- UUID primary keys (ADR-0004) — set the Rails-wide primary key generator
  default, do not do this ad hoc per migration.
- Every tenant-owned table gets a `tenant_id` column (UUID, FK to
  `tenants`), an index on it, and RLS enabled + a tenant isolation policy
  **in the same migration** that creates the table — never as a follow-up
  migration (ADR-0002, ADR-0003).
- Use `decimal` (with explicit precision/scale) for any monetary column,
  never `float`. Store currency as an explicit column (e.g. ISO 4217 code
  string), never assume a single implicit currency.
- Use `date` for calendar dates with no time-of-day meaning (effective
  date, commencement date, expiration date) and `datetime`/`timestamp`
  only where time-of-day genuinely matters (e.g. `created_at`).
- Add database constraints (foreign keys, check constraints, partial
  unique indexes) for invariants that must always hold — do not rely on
  model validations alone for data integrity.
- Add indexes for foreign keys and for columns used in RLS policy
  predicates (typically `tenant_id`).

## RLS migration checklist (apply to every tenant-owned table)

1. Create the table with `tenant_id` and the rest of its columns.
2. `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
3. `ALTER TABLE ... FORCE ROW LEVEL SECURITY;` (so even the table owner
   role is subject to the policy, unless there's an explicit, documented
   reason not to).
4. Create the tenant isolation policy against the session-local tenant
   setting.
5. Confirm the application's database role is not a superuser and does
   not have `BYPASSRLS`.
6. Add the raw-SQL-level RLS test described in
   `docs/runbooks/testing.md`.

## Commands (verified, exercised against the Identity & Tenancy module)

```
cd apps/api
bin/rails db:create
RAILS_ENV=development bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate       # or db:test:prepare after a schema_format change
bin/rails db:rollback                      # when a migration needs to be reverted
```

## Do not

Do not disable or weaken RLS to get a migration/test to pass. Do not add a
tenant-owned table without `tenant_id` + RLS in the same change. Do not
use `default_scope` as a substitute for RLS.
