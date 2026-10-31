# Testing Runbook

## Current state

RSpec is the backend framework (`apps/api/spec/`: models, policies,
requests, services, security); there is no `apps/api/test/`. Specs that
touch tenant-owned rows wrap them in `with_tenant(...)`
(`spec/support/tenant_context_helper.rb`) — FORCE RLS applies to the test
role too. `apps/web` has no test runner installed at all.

## Backend commands (verified, exercised against Identity & Portfolio)

```
cd apps/api
bundle exec rspec              # once specs exist
bin/rubocop                    # Omakase style, already configured via .rubocop.yml
bin/brakeman --no-pager        # static security analysis, already in CI
```

All three run in `.github/workflows/ci.yml` (repo root — GitHub ignores
workflows anywhere else). The `api-test` job creates the
`lease_intelligence` role with `NOSUPERUSER NOBYPASSRLS CREATEDB`, fails
if it could bypass RLS, then loads `db/structure.sql`
(`db:create db:schema:load`) — never run the suite as `postgres`, or RLS
specs pass vacuously. Brakeman reads `config/brakeman.ignore`; the only
entry is the Rails 8.0 end-of-life notice (remove it with the Rails
upgrade). A green CI is evidence only for what the specs cover.

## Frontend commands (verified present in apps/web/package.json)

```
cd apps/web
npm run build     # runs `tsc -b` then `vite build` — typecheck gate
npm run lint       # oxlint
```

No `npm test` exists — no test runner is installed. Adding one (e.g.
Vitest + React Testing Library) needs an explicit justification per root
`CLAUDE.md` §9 before being added, but is a reasonable near-term addition
once real components exist to test.

## Mandatory coverage once domain code exists (per apps/api/CLAUDE.md §13)

Models, policies, services, API request specs, tenant isolation
(including RLS-level tests independent of application authorization),
background jobs, document processing, contract versioning, financial
calculations, review workflows. For security-sensitive features, test both
the permitted and the denied path explicitly.

## Tenant isolation test pattern (established — copy it for each new
tenant-owned model)

At minimum three layers: (1) policy spec proving deny for a
cross-tenant actor, (2) request spec proving a cross-tenant request
returns 403/404 rather than leaking data, (3) a raw-SQL-level spec that
sets a different tenant context and proves Postgres RLS itself refuses
the row, independent of any Rails-level authorization code. See
`.claude/rules/multi-tenancy.md` and the `tenant-isolation-review` skill.

Reference implementation (Portfolio): `spec/support/portfolio_policy_examples.rb`
(role matrix + cross-tenant deny + Scope), `spec/requests/api/v1/properties_spec.rb`
(cross-tenant show/update is a 404 identical to a nonexistent id, header
for another tenant is a 403, body `tenant_id` ignored, connection left
clean), and the raw-SQL blocks in `spec/security/row_level_security_spec.rb`
(SELECT/UPDATE/DELETE/INSERT/tenant-move denied with no model involved).
When asserting a database error inside `with_tenant`, put the `expect {}`
*outside* the block so the savepoint rolls back.

## Do not

Do not report a test suite as passing without having run the exact
command above. Do not remove or skip a failing test to make CI green —
fix the underlying issue or, if the test is genuinely wrong, say so
explicitly and get agreement before deleting it.
