# ADR-0006: Background Processing (Sidekiq)

## Context

Document OCR and AI extraction are inherently slow, I/O- and
provider-latency-bound operations that must not block request/response
cycles. The product's stated engineering context (`apps/api/CLAUDE.md`
§4) names Sidekiq + Redis as the background processing stack.

## Problem

Rails 8's generator defaults (already present in `apps/api/Gemfile` and
wired into `config/environments/production.rb`) use Solid Queue
(DB-backed), not Sidekiq. The `Gemfile` currently contains **both**
`sidekiq` and `solid_queue`/`solid_cache`/`solid_cable`, with only Solid
Queue actually wired as the ActiveJob adapter. This is an unresolved
conflict, not a decision — see root `CLAUDE.md` §3.

## Decision

**Sidekiq + Redis** (decided by the product owner, 2026-10-31). Solid
Queue is removed. Active Job uses `:sidekiq` in every environment except
test, which uses the `:test` adapter so the suite never needs Redis.
`solid_cache` and `solid_cable` are kept — they back Rails.cache and
Action Cable, which this decision does not cover.

## Alternatives considered

- **Sidekiq + Redis** (named in `apps/api/CLAUDE.md` §4): mature
  ecosystem, strong introspection (Sidekiq Web UI), well-understood retry/
  backoff semantics, widely documented for Rails background processing at
  scale. Cost: requires standing up and operating a Redis service in every
  environment (local dev, CI, production) — currently absent (CI's Redis
  service block is commented out; `infrastructure/` has no
  docker-compose; no Redis config anywhere).
- **Solid Queue** (Rails 8 default, already wired): no extra infra
  dependency — uses the existing PostgreSQL database; one less moving
  part operationally; newer and less battle-tested at high throughput
  than Sidekiq; less mature introspection tooling as of this writing.

## Consequences of the decision

- Redis is now required to run jobs in development and production
  (`REDIS_URL`; mandatory in production, defaults to
  `redis://localhost:6379/0` elsewhere). The web process boots without
  Redis; only enqueueing and the worker need it.
- Jobs run in a separate worker process (`bin/jobs` → `sidekiq -C
  config/sidekiq.yml`), never inside Puma; Kamal has a `job` role for it.
- Periodic jobs need an extra decision later (Sidekiq OSS has no
  scheduler: sidekiq-cron, Sidekiq Enterprise, or an external cron).
- The Sidekiq Web UI is not mounted: exposing it needs authentication and
  a security review.

## Consequences (of leaving this undecided — historical)

Any job written today has no settled target adapter. Writing jobs against
Solid Queue (since it's already wired) and later migrating to Sidekiq
would mean re-pointing ActiveJob's adapter and standing up Redis
everywhere — a meaningful but mechanical migration, since ActiveJob is an
abstraction over both. The bigger cost of leaving this undecided is
infrastructure drift: CI and docker-compose scaffolding can't be finalized
until the adapter is chosen.

## Security implications

Background job isolation (tenant context re-establishment per job, no
credential leakage into job logs/arguments) — see
`docs/architecture/multi-tenancy.md` and `.claude/rules/multi-tenancy.md`.
Implemented by `ApplicationJob#within_tenant(tenant_id)`: looks up the
tenant, refuses a missing/unknown/inactive one with `TenantContextError`,
and runs the block in `TenantContext` (SET LOCAL, cleared afterwards).

Job payloads are stored in Redis in plain text, and Sidekiq's own error
handler logs the full payload (arguments included) when a job raises —
`log_arguments = false` only silences Active Job's logging. Arguments
must therefore be ids only. Production Redis must use authentication and
TLS (`rediss://`).

## Implementation status

**Implemented.** `solid_queue` gem, `config/queue.yml`,
`config/recurring.yml`, `db/queue_schema.rb`, the Puma plugin and the
production `queue` database were removed. Added: adapter in
`config/application.rb` (`:test` in `config/environments/test.rb`),
`config/sidekiq.yml`, `config/initializers/sidekiq.rb`, `bin/jobs`,
`ApplicationJob#within_tenant` + `spec/jobs/application_job_spec.rb`, Kamal
`job` role. Verified end to end in development against a local Redis.
Not done (deliberately): CI Redis service (the suite uses the test
adapter), `infrastructure/docker-compose.yml` (root `CLAUDE.md` §3.4 —
local Redis runs natively for now).
