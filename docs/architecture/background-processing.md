# Background Processing Architecture

Status: unresolved — see root `CLAUDE.md` §3 point 1 and ADR-006. This
document states the requirement and the current gap; it does not claim a
resolved implementation.

## Requirement

Document processing (OCR, AI extraction) and any other multi-step or
slow operation must run asynchronously, must be idempotent (safe to retry
after a crash or duplicate enqueue), and must explicitly establish tenant
context before touching tenant-owned data (see
`docs/architecture/multi-tenancy.md` — background job isolation).

## Current state in the repository

`apps/api/Gemfile` declares both:

- `solid_queue` / `solid_cache` / `solid_cable` — Rails 8 generator
  defaults, database-backed, and **already wired**: `
  config.active_job.queue_adapter = :solid_queue` in
  `config/environments/production.rb`, with `config/queue.yml` present.
- `sidekiq` (~> 8.1) — added on top, pulling in `redis-client`, but **not
  wired**: no `config/sidekiq.yml`, no initializer, no Redis service
  declared anywhere (not in `apps/api/.github/workflows/ci.yml`, which has
  its Redis service block commented out; not in `infrastructure/`, which is
  empty).

`apps/api/CLAUDE.md` §4 states the product's intended stack as "Sidekiq +
Redis." This has not been reconciled with the Rails 8 defaults actually
wired in the generated app.

## Resolution required before writing any background job

Pick one adapter and remove the other's unused configuration/gem, per
ADR-006:

- **Solid Queue** — simpler ops (no Redis service to run/monitor), fully
  DB-backed, good fit for a modular monolith that already depends on
  Postgres being available; weaker fit if job volume/throughput later needs
  dedicated infra separate from the primary database.
- **Sidekiq + Redis** — more mature ecosystem, better introspection/UI,
  what the product instructions currently name explicitly; requires running
  and operating a Redis service (local dev via `infrastructure/`, which
  does not exist yet, and a CI service, currently commented out).

This decision should be made and recorded as an ADR update (not just this
doc) before the first `ApplicationJob` subclass is written.

## Job design rules (apply regardless of which adapter is chosen)

- Jobs receive primitive identifiers (IDs), not ActiveRecord objects, as
  arguments.
- Jobs are idempotent: re-running a job with the same arguments must not
  double-create records or double-charge an external provider.
- Jobs explicitly set and tear down tenant context.
- Jobs handle external provider failures (timeout, rate limit, malformed
  response) and leave the underlying record in a reviewable failure state
  rather than raising into an opaque retry loop with no visibility.
