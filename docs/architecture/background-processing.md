# Background Processing Architecture

Status: **Sidekiq + Redis, implemented** (ADR-0006). No product job
exists yet — the first will be document processing (OCR, AI extraction).

## Requirement

Document processing (OCR, AI extraction) and any other multi-step or
slow operation must run asynchronously, must be idempotent (safe to retry
after a crash or duplicate enqueue), and must explicitly establish tenant
context before touching tenant-owned data (see
`docs/architecture/multi-tenancy.md` — background job isolation).

## How it is wired

- Adapter: `config.active_job.queue_adapter = :sidekiq` in
  `config/application.rb`; `:test` in `config/environments/test.rb`, so
  the spec suite and CI never need Redis.
- Redis: `config/initializers/sidekiq.rb` reads `REDIS_URL` — required in
  production (boot fails without it), `redis://localhost:6379/0` default
  elsewhere.
- Worker: `bin/jobs` (`bundle exec sidekiq -C config/sidekiq.yml`), a
  separate process — never inside Puma. Kamal runs it as the `job` role.
- Queues (`config/sidekiq.yml`): `default` (weight 2), `mailers`
  (weight 1); concurrency from `SIDEKIQ_CONCURRENCY` (default 5). Add a
  dedicated queue (e.g. `documents`) together with the first job that
  needs it, so slow provider calls cannot starve short jobs.
- Retries: Sidekiq's defaults (exponential backoff, then the dead set).
  Per-job `retry_on`/`discard_on` only where a failure is known to be
  transient or permanent.

## Tenant context in jobs

`ApplicationJob#within_tenant(tenant_id) { ... }` — the only supported way
for a job to touch tenant-owned data:

```ruby
class ExtractDocumentJob < ApplicationJob
  def perform(tenant_id, document_version_id)
    version = within_tenant(tenant_id) { DocumentVersion.find(document_version_id) }
    output = provider.extract(...)            # slow call: outside the transaction
    within_tenant(tenant_id) { record_result(version, output) }
  end
end
```

- A blank, unknown or non-active tenant raises
  `ApplicationJob::TenantContextError`; there is no fallback tenant.
- The block runs inside `TenantContext.activate` (one transaction,
  `SET LOCAL`, cleared afterwards), so keep provider calls out of it.
- Covered by `spec/jobs/application_job_spec.rb`.

## Job design rules

- Jobs receive primitive identifiers (IDs), not ActiveRecord objects, as
  arguments. Payloads sit in Redis in plain text and Sidekiq logs the full
  payload when a job raises (`log_arguments = false` only silences Active
  Job's own logging) — never pass document text, personal data or secrets.
- Jobs are idempotent: re-running a job with the same arguments must not
  double-create records or double-charge an external provider.
- Jobs explicitly set and tear down tenant context (`within_tenant`).
- Jobs handle external provider failures (timeout, rate limit, malformed
  response) and leave the underlying record in a reviewable failure state
  rather than raising into an opaque retry loop with no visibility.

## Not built yet

- Sidekiq Web UI (needs authentication + security review before mounting).
- Periodic jobs (Sidekiq OSS has no scheduler — decide when the first one
  is needed).
- `infrastructure/docker-compose.yml` for Redis/Postgres.
