# Backend Architecture

Status: planned conventions for a codebase that does not have domain code
yet (`apps/api/app/models` only has `ApplicationRecord`; `app/controllers`
only has `ApplicationController`).

## Stack as actually declared in `apps/api/Gemfile`

Rails ~> 8.0.5, pg, puma, Devise 5, Pundit 2.5, Sidekiq 8.1 (the Active
Job adapter — ADR-006), solid_cache/solid_cable (Rails 8 defaults for
cache and Action Cable), rack-attack, rspec-rails 8, factory_bot_rails
6.5, shoulda-matchers 8, brakeman, rubocop-rails-omakase, bootsnap, kamal,
thruster.

`rack-cors` is deliberately not used — the SPA is same-origin (ADR-0013).
Not yet in the Gemfile but implied by product requirements: an image/PDF processing
gem for OCR pre-processing if needed, a JSON schema validation gem for
structured AI output (or hand-rolled validation).

## Layering

- `app/controllers` — thin. Authenticate, authorize via Pundit, delegate to
  a service/query object, render. No business rules, no direct complex
  ActiveRecord queries beyond simple finds.
- `app/models` — ActiveRecord models with validations, associations, and
  small, well-named instance methods. No "god models." Scopes are explicit
  and named, not hidden in callbacks.
- `app/services` (or `app/domains/<domain>/services`) — the home for
  multi-step business workflows (e.g., "approve an extracted field and
  materialize a contractual condition"). Service objects should have a
  single public entry point and return a result object, not raise for
  expected business outcomes.
- `app/policies` — Pundit policies, one per resource, tested for both
  allow and deny cases.
- `app/jobs` — background job classes. Must be idempotent and must
  explicitly set tenant context before touching tenant-owned data.
- `app/serializers` (to be chosen/added) — explicit JSON shape per
  resource, not raw `.to_json` on ActiveRecord objects.

## Database access rules

- Never bypass RLS with a superuser/admin connection in request-serving
  code.
- Prefer explicit, named scopes over implicit `default_scope` for tenant
  filtering — `default_scope` is too easy to silently bypass with `.unscoped`
  and gives a false sense of safety; RLS is the real boundary, scopes are a
  convenience and a second line of defense.
- Use database constraints (foreign keys, check constraints, partial
  unique indexes) to enforce invariants that matter, not just model
  validations.

## Error handling

Handle external provider failures (OCR/LLM/storage) explicitly — timeouts,
rate limits, malformed responses. Do not assume a third-party API is always
available; background jobs that call these providers must have retry/backoff
and must surface terminal failures to a reviewable status, not swallow them.

## What does not exist yet (do not assume)

No serializer library (plain serializer classes in `app/serializers`).
Pagination is the in-house `Paginated` controller concern (offset,
`?page=&per_page=` up to 100, `meta` with totals; invalid values are 400)
— no pagination gem. Domain code lives in `app/services/identity/` and
`app/services/portfolio/` (services + query objects); services return
`ServiceResult` (validation failures carry the model's
`ActiveModel::Errors`, rendered as 422 `validation_failed` with
`details`). Tenant-owned record policies inherit `TenantOwnedPolicy`.
Rack::Attack only throttles sign-in (`config/initializers/rack_attack.rb`).
