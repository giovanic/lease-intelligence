module DocumentText
  # Queues a text extraction of a DocumentVersion (docs/adr/0016): called by
  # Documents::VersionWriter on every upload (requested_by: nil) and by the
  # reprocess endpoint. Must run in the version's tenant context. The job is
  # pushed to Redis only after the caller's transaction commits
  # (ExtractDocumentTextJob.enqueue_after_transaction_commit).
  #
  # At most one attempt is in flight per version: while one is
  # pending/running this fails with "in_progress", unless it has been stuck
  # longer than DocumentTextExtraction::ABANDONED_AFTER (worker crash) — then
  # it is closed as failed/abandoned and a new one starts.
  #
  # success(DocumentTextExtraction) | failure("in_progress")
  class RequestExtraction
    ACTIVE_INDEX = "idx_document_text_extractions_one_active_per_version".freeze

    def self.call(version:, requested_by: nil)
      extraction = DocumentTextExtraction.transaction(requires_new: true) do
        active = DocumentTextExtraction.active.lock.find_by(document_version_id: version.id)
        if active.nil? || close_abandoned(active)
          DocumentTextExtraction.create!(tenant_id: version.tenant_id, document_version: version,
            requested_by: requested_by)
        end
      end
      return ServiceResult.failure("in_progress") unless extraction

      ExtractDocumentTextJob.perform_later(extraction.tenant_id, extraction.id)
      ServiceResult.success(extraction)
    rescue ActiveRecord::RecordNotUnique => error
      # A concurrent request inserted the active attempt first.
      raise unless error.message.include?(ACTIVE_INDEX)

      ServiceResult.failure("in_progress")
    end

    def self.close_abandoned(extraction)
      return false unless extraction.abandoned?

      extraction.update!(status: :failed, error_code: "abandoned", finished_at: Time.current)
    end
    private_class_method :close_abandoned
  end
end
