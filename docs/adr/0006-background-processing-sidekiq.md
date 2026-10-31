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

**Not yet made.** This ADR records the conflict and the two live options;
it must be resolved — by updating this ADR with a chosen option and then
implementing it — before any `ApplicationJob` subclass is written for
document processing.

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

## Consequences (of leaving this undecided)

Any job written today has no settled target adapter. Writing jobs against
Solid Queue (since it's already wired) and later migrating to Sidekiq
would mean re-pointing ActiveJob's adapter and standing up Redis
everywhere — a meaningful but mechanical migration, since ActiveJob is an
abstraction over both. The bigger cost of leaving this undecided is
infrastructure drift: CI and docker-compose scaffolding can't be finalized
until the adapter is chosen.

## Security implications

Whichever adapter is chosen, background job isolation (tenant context
re-establishment per job, no credential leakage into job logs/arguments)
applies identically — see `docs/architecture/multi-tenancy.md` and
`.claude/rules/multi-tenancy.md`.

## Implementation status

**Conflicted — not decided, not implemented.** Resolve by: (1) deciding
Sidekiq+Redis vs. Solid Queue with the product owner, (2) removing the
unused gem(s)/config, (3) if Sidekiq is chosen, adding `infrastructure/`
docker-compose with Redis, uncommenting the CI Redis service block, adding
`config/sidekiq.yml` and the ActiveJob adapter config, (4) updating this
ADR's Decision section and `docs/architecture/background-processing.md`.
