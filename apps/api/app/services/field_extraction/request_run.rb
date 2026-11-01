module FieldExtraction
  # Queues an AI field extraction of a DocumentVersion (docs/adr/0017): called
  # by ExtractDocumentTextJob once a text extraction succeeds
  # (requested_by: nil, text_extraction: that one) and by the reprocess
  # endpoint (over the version's latest succeeded text). Must run in the
  # version's tenant context. The job is pushed to Redis only after the
  # caller's transaction commits
  # (ExtractContractFieldsJob.enqueue_after_transaction_commit).
  #
  # At most one run is in flight per version: while one is pending/running
  # this fails with "in_progress", unless it has been stuck longer than
  # ExtractionRun::ABANDONED_AFTER (worker crash) — then it is closed as
  # failed/abandoned and a new one starts.
  #
  # success(ExtractionRun) | failure("unavailable" | "text_not_ready" | "in_progress")
  class RequestRun
    ACTIVE_INDEX = "idx_extraction_runs_one_active_per_version".freeze

    def self.call(version:, text_extraction: nil, requested_by: nil, provider: Llm.provider)
      return ServiceResult.failure("unavailable") if provider.nil?

      text_extraction ||= version.text_extractions.succeeded.last
      return ServiceResult.failure("text_not_ready") unless text_extraction&.succeeded?

      run = ExtractionRun.transaction(requires_new: true) do
        active = ExtractionRun.active.lock.find_by(document_version_id: version.id)
        if active.nil? || close_abandoned(active)
          ExtractionRun.create!(
            tenant_id: version.tenant_id, document_version: version, text_extraction: text_extraction,
            requested_by: requested_by, provider: provider.name, model: provider.model, effort: provider.effort,
            prompt_version: Prompt::VERSION
          )
        end
      end
      return ServiceResult.failure("in_progress") unless run

      ExtractContractFieldsJob.perform_later(run.tenant_id, run.id)
      ServiceResult.success(run)
    rescue ActiveRecord::RecordNotUnique => error
      # A concurrent request inserted the active run first.
      raise unless error.message.include?(ACTIVE_INDEX)

      ServiceResult.failure("in_progress")
    end

    def self.close_abandoned(run)
      return false unless run.abandoned?

      run.update!(status: :failed, error_code: "abandoned", finished_at: Time.current)
    end
    private_class_method :close_abandoned
  end
end
