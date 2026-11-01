# Troubleshooting Runbook

This runbook will grow as real issues are encountered; it currently
records only what is knowable from the harness setup inspection.

## "CORS error" when apps/web calls apps/api

Expected until resolved — `rack-cors` is not in `apps/api/Gemfile` and
`config/initializers/cors.rb` is the unmodified template (commented out).
Add the gem, configure allowed origins (the dev SPA's Vite origin plus
whatever the production SPA origin will be), uncomment and configure the
middleware.

## "Which background job adapter is actually running my job?"

Sidekiq in every environment (`config/application.rb`), the `:test`
adapter in specs (`config/environments/test.rb`) — ADR-0006. A job that is
enqueued but never runs usually means no worker (`bin/jobs`) or the worker
and the API point at different Redis databases (`REDIS_URL`). A job that
raises `ApplicationJob::TenantContextError` was enqueued without a valid,
active tenant id — fix the caller, never add a fallback tenant.

## "RLS is blocking a query I expect to succeed"

First check: is the session's tenant context actually set for this
connection/transaction (`SET LOCAL app.current_tenant_id = ...`)? A
missing or stale tenant context is the most likely cause, not a bug in
the policy. Do not respond to this by disabling RLS — see root
`CLAUDE.md` §4 and ADR-0003.

## `db:test:prepare` fails with `unrecognized configuration parameter "transaction_timeout"`

`db/structure.sql` was dumped by `pg_dump` 17 (Ubuntu's `pg_wrapper`
picks the newest installed client) while the server — and CI's
`postgres:16` — is 16. Re-dump with the 16 client instead of editing the
file: `PATH=/usr/lib/postgresql/16/bin:$PATH bin/rails db:schema:dump`
(also prefix `db:migrate`/`db:rollback`, which dump on success).

## "Test database schema doesn't match"

Standard Rails symptom of pending migrations — run
`bin/rails db:test:prepare`. Not yet encountered in practice since no
migrations exist, but documented for when they do.

## "apps/api has a .git with no commits, there's no root .git"

This is the actual repository state found during harness setup (see root
`CLAUDE.md` §3, point 6). Confirm the intended topology with the user
before assuming either "one monorepo" or "independent per-app repos."
