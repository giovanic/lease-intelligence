---
applies_to: apps/api/**
---

# Backend Rules

- Controllers: parse params, authorize via Pundit, delegate to a service
  or query object, render. No business logic, no direct multi-step
  ActiveRecord workflows inline in an action.
- Service objects: one public entry point per object, return a result
  object (e.g. success/failure + payload) rather than raising for
  expected business outcomes. Reserve exceptions for truly exceptional
  states.
- Models: validations, associations, small well-named methods. No
  callbacks that hide control flow a reader can't trace from the call
  site (e.g. avoid `after_save` chains that trigger unrelated side
  effects — make side effects explicit in the service object instead).
- Never use `default_scope` for tenant filtering — see
  `.claude/rules/multi-tenancy.md`. RLS is the enforced boundary.
- Money: `decimal` columns with explicit precision/scale, explicit
  currency code column. Never `float`/`Float` for a monetary value,
  anywhere — model, service, or serializer.
- Dates: `date` type for calendar dates with no time-of-day meaning
  (effective date, commencement date, expiration date); `datetime` only
  where time-of-day genuinely matters. Never conflate upload date,
  signature date, effective date, commencement date, and expiration date
  — they are distinct columns (see `docs/domain/leases.md`).
- Background jobs: idempotent, take primitive IDs as arguments (not
  ActiveRecord objects), explicitly establish tenant context, handle
  external provider failures without silently swallowing them.
- External providers (OCR/LLM/storage): never assume availability; handle
  timeouts/rate limits/malformed responses explicitly through the
  provider abstraction (ADR-0008, ADR-0009), not ad hoc per call site.
- Before adding a gem: state the architectural justification (per root
  `CLAUDE.md` §4/§9). Check `apps/api/Gemfile` first — the former Sidekiq/Solid
  Queue conflict (ADR-0006, now resolved for Sidekiq) existed precisely
  because this wasn't done rigorously; don't repeat that pattern.
- Run `bin/rubocop` (Omakase style, already configured) and
  `bin/brakeman --no-pager` before considering backend work done.
