# Turns one DocumentTextExtraction into per-page text
# (docs/adr/0016-document-text-extraction.md). Queued by
# DocumentText::RequestExtraction with ids only.
#
# Three steps, so no transaction stays open while OCR runs:
# 1. within_tenant: mark the attempt running (StartExtraction);
# 2. outside any transaction: download + native text + OCR (ExtractPages);
# 3. within_tenant: store pages + outcome (RecordOutcome).
# A finished attempt makes the job a no-op, so a duplicate delivery or a
# retry never stores the pages twice.
#
# Expected failures (unreadable file, timeout, OCR missing, storage down)
# are recorded as `failed` with an error code by step 3 and not retried:
# reprocessing is a human decision. Anything else is retried by Active Job;
# when the attempts run out the extraction is marked `internal_error`. If
# even that is impossible (tenant gone or suspended), the error is raised
# and Sidekiq — with no retries of its own — moves the job to the dead set.
class ExtractDocumentTextJob < ApplicationJob
  ATTEMPTS = 3

  queue_as :documents
  # Every caller is inside a transaction (the upload, the request): pushing
  # the job before it commits could let a worker look for a row it cannot
  # see yet.
  self.enqueue_after_transaction_commit = true
  # Retries are Active Job's (below); Sidekiq's own 25 would retry a
  # recorded failure for weeks.
  sidekiq_options retry: 0

  retry_on StandardError, attempts: ATTEMPTS, wait: :polynomially_longer do |job, error|
    job.record_internal_error(error)
  end

  def perform(tenant_id, extraction_id)
    started = within_tenant(tenant_id) { DocumentText::StartExtraction.call(extraction_id) }
    return if started.failure?

    source = started.value
    result = DocumentText::ExtractPages.call(storage_key: source.storage_key, content_type: source.content_type,
      ocr: Ocr.provider)
    within_tenant(tenant_id) { DocumentText::RecordOutcome.call(extraction_id: extraction_id, result: result) }
  end

  # Called once the retries are exhausted. Re-raises when the outcome cannot
  # be recorded, so the failure stays visible.
  def record_internal_error(error)
    raise error if error.is_a?(TenantContextError)

    tenant_id, extraction_id = arguments
    within_tenant(tenant_id) do
      DocumentText::RecordOutcome.call(extraction_id: extraction_id, result: ServiceResult.failure("internal_error"))
    end
  end
end
