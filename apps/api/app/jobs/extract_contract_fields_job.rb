# Turns one ExtractionRun into candidate fields with evidence
# (docs/adr/0017-contract-field-extraction-claude.md). Queued by
# FieldExtraction::RequestRun with ids only.
#
# Three steps, so no transaction stays open during the provider call:
# 1. within_tenant: mark the run running and load its pages (StartRun);
# 2. outside any transaction: prompt + provider + validation (ExtractFields);
# 3. within_tenant: store fields, evidence + outcome (RecordOutcome).
# A finished run makes the job a no-op, so a duplicate delivery or a retry
# never stores the fields twice.
#
# Expected failures (rate limit, provider down, timeout, truncated,
# refused, invalid answer, text too long) are recorded as `failed` with an
# error code by step 3 and not retried: the provider client already
# retried transient errors, and reprocessing — which costs a new call — is
# a human decision. Anything else is retried by Active Job; when the
# attempts run out the run is marked `internal_error`. If even that is
# impossible (tenant gone or suspended), the error is raised and Sidekiq —
# with no retries of its own — moves the job to the dead set. A provider
# that is no longer configured is an error too: the run stays visible.
class ExtractContractFieldsJob < ApplicationJob
  ATTEMPTS = 3

  # Provider not configured anymore (the key was removed after the run was
  # queued).
  class ProviderMissingError < StandardError; end

  queue_as :documents
  # Every caller is inside a transaction (the text job's last step, the
  # request): pushing the job before it commits could let a worker look for
  # a row it cannot see yet.
  self.enqueue_after_transaction_commit = true
  # Retries are Active Job's (below); Sidekiq's own 25 would retry a
  # recorded failure for weeks.
  sidekiq_options retry: 0

  retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
    job.record_internal_error(error)
  end

  def perform(tenant_id, run_id)
    started = within_tenant(tenant_id) { FieldExtraction::StartRun.call(run_id) }
    return if started.failure?

    provider = Llm.provider
    raise ProviderMissingError, "no LLM provider configured" if provider.nil?

    result = FieldExtraction::ExtractFields.call(pages: started.value, provider: provider)
    within_tenant(tenant_id) { FieldExtraction::RecordOutcome.call(run_id: run_id, result: result) }
  end

  # Called once the retries are exhausted. Re-raises when the outcome cannot
  # be recorded, so the failure stays visible.
  def record_internal_error(error)
    raise error if error.is_a?(TenantContextError)

    tenant_id, run_id = arguments
    within_tenant(tenant_id) do
      FieldExtraction::RecordOutcome.call(run_id: run_id, result: ServiceResult.failure("internal_error"))
    end
  end
end
