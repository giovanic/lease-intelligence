module DocumentText
  # First step of ExtractDocumentTextJob, in the tenant context: marks the
  # attempt `running` and returns what ExtractPages needs to read the file.
  # A finished attempt (duplicate delivery, or closed as abandoned) is a
  # failure, and the job stops there. A `running` one is resumed: nothing
  # was stored yet, since pages are written only by RecordOutcome.
  #
  # success(Source) | failure("finished")
  class StartExtraction
    Source = Data.define(:storage_key, :content_type)

    def self.call(extraction_id)
      extraction = DocumentTextExtraction.lock.find(extraction_id)
      return ServiceResult.failure("finished") if extraction.finished?

      extraction.update!(status: :running, started_at: extraction.started_at || Time.current)
      version = extraction.document_version
      ServiceResult.success(Source.new(storage_key: version.storage_key, content_type: version.content_type))
    end
  end
end
