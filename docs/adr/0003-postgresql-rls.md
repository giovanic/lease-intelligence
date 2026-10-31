# ADR-0003: PostgreSQL Row-Level Security

## Context

ADR-0002 commits to shared-schema multi-tenancy, which requires a
database-enforced isolation mechanism independent of application code
correctness.

## Problem

Application-level tenant scoping (scopes, `default_scope`, controller
filters) can be bypassed by a single bug: a missing `.where(tenant: ...)`,
a `.unscoped` call, a raw SQL query, a background job that forgets to set
tenant context. How do we guarantee isolation even when application code
has a bug?

## Decision

Enable PostgreSQL Row-Level Security on every tenant-owned table, with
policies that restrict visible and writable rows to the tenant identified
by a per-transaction session setting (e.g.
`current_setting('app.current_tenant_id')`). The application's database
role must not have `BYPASSRLS` and must not be a superuser.

## Alternatives considered

- **Rely solely on Rails-level scoping** — rejected: no backstop against
  application bugs, which is precisely the failure mode that matters most
  for this product (financial/legal contract data).
- **Application-level query auditing/linting only** — rejected as the
  primary control: useful as an additional check, but cannot catch every
  code path (console access, ad hoc scripts, future contributors unaware
  of the convention).
- **RLS as a secondary/optional layer, app-level scoping as primary** —
  rejected: inverts the correct trust hierarchy; the database must be the
  authority, not a convenience check.

## Consequences

- Positive: isolation holds even against buggy or malicious application
  code, ad hoc Rails console usage, or a future unscoped raw SQL query.
- Negative: adds real engineering cost — every migration touching a
  tenant-owned table must also manage RLS policies; connection pooling
  requires care (`SET LOCAL` per transaction, not per connection) to avoid
  tenant-context leakage across pooled connections; testing RLS requires
  dedicated test setup (a non-bypassing database role in the test
  environment too, not just production).
- Rails console / admin tooling must explicitly and auditably set a
  tenant context (or explicitly, auditably, operate without one for
  genuine cross-tenant admin needs) — there is no implicit free pass.

## Security implications

This is the primary technical control preventing cross-tenant data
exposure. Any change that appears to require disabling or bypassing RLS
(e.g., "the test won't pass with RLS on") is a signal of a design problem
to fix, never a justification to disable it — see root `CLAUDE.md` §4 and
`.claude/rules/security.md`.

## Addendum: schema format, and the bootstrap/self-visibility refinement

Two things were learned building the first RLS-protected tables
(Identity & Tenancy — `memberships`, `invitations`) that refine, not
replace, the decision above:

1. **`db/schema.rb` (Rails' default Ruby schema format) cannot represent
   RLS policies, `FORCE ROW LEVEL SECURITY`, or the custom SQL functions
   RLS policies depend on** — it only captures tables, columns, indexes,
   foreign keys, and check constraints. Rebuilding any environment from
   `schema.rb` (e.g. `db:test:prepare`) silently produces a database with
   **no RLS at all**, which was caught by the raw-SQL isolation tests
   failing after a fresh `db:test:prepare`. Fix:
   `config.active_record.schema_format = :sql` in `config/application.rb`,
   so Rails dumps/loads `db/structure.sql` via `pg_dump`/`psql` instead,
   which captures the policies, `FORCE ROW LEVEL SECURITY`, and functions
   correctly. **Any future PostgreSQL-RLS-based Rails app must set this
   from the start** — it is not optional once a single `execute "CREATE
   POLICY ..."` appears in a migration.
2. **Bootstrap problem:** before a user has selected a tenant, the app
   still needs to answer "which organizations am I in," which requires
   reading `memberships` across ALL of a user's tenants — a query that
   is inherently not scoped to one `current_tenant_id`. Resolved by
   adding a second per-transaction session setting, `app.current_user_id`
   (alongside `app.current_tenant_id`), and a second, narrower PERMISSIVE
   policy on `memberships` (`memberships_self_visibility`, SELECT-only)
   that lets a user see their own membership rows regardless of the
   active tenant context. Writes still require the tenant-isolation
   policy to match, so this cannot be used to self-escalate a role or
   modify a membership without that tenant's context active. See
   `db/migrate/20261031133227_create_memberships.rb` and
   `app/services/tenant_context.rb`.

A related, deliberately **unresolved** question for later: `invitations`
accept-by-token needs a similar bootstrap mechanism (the invitee has no
tenant context at all), and a blanket SELECT-by-token policy would be
unsafe (it would let the app role read every tenant's invitations, not
just the one matching the token actually being looked up). The
correct-but-not-yet-built approach is a third session setting acting as a
one-shot capability token (`SET LOCAL app.invitation_lookup_token`),
checked by an additional policy `token = current_setting(...)`, set only
for the duration of that one lookup. Flagged for whenever the
accept-invitation endpoint is built — see `docs/domain/identity.md`.

## Implementation status

**Implemented for the Identity & Tenancy module** (`tenants`,
`memberships`, `invitations` — see `db/migrate/202610311332*`). `tenants`
and `users` are intentionally not RLS-protected (see
`docs/adr/0002-shared-schema-multi-tenancy.md` and
`docs/domain/identity.md`). Verified by:
`spec/security/row_level_security_spec.rb` (ActiveRecord-level,
role-enforced) plus a manual raw-`psql`-as-the-app-role smoke test during
implementation. Not yet extended to any other module's tables — each
future tenant-owned table must repeat the full checklist in
`docs/runbooks/database.md`, it is not automatic.
