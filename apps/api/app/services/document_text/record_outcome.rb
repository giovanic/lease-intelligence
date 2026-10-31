module DocumentText
  # Last step of ExtractDocumentTextJob, in the tenant context: stores the
  # outcome of ExtractPages on the attempt — every page plus `succeeded` in
  # one transaction, or `failed` with the error code. An attempt that is
  # already finished is left alone (a duplicate job, or one closed as
  # abandoned while this run was still going), so it is never written twice.
  #
  # `result`: the ServiceResult of ExtractPages.
  # Returns success(DocumentTextExtraction) | failure("finished").
  class RecordOutcome
    def self.call(extraction_id:, result:)
      DocumentTextExtraction.transaction(requires_new: true) do
        extraction = DocumentTextExtraction.lock.find(extraction_id)
        next ServiceResult.failure("finished") if extraction.finished?

        result.success? ? succeed(extraction, result.value) : record_failure(extraction, result.error)
        ServiceResult.success(extraction)
      end
    end

    def self.succeed(extraction, extracted)
      now = Time.current
      # One INSERT per page, not insert_all: insert_all inlines the text as
      # SQL literals, which a debug-level log prints in full; as binds it is
      # masked by filter_parameters (/\Atext\z/).
      extracted.pages.each do |page|
        DocumentTextPage.create!(tenant_id: extraction.tenant_id, text_extraction: extraction,
          page_number: page.number, source: page.source, text: page.text, created_at: now)
      end
      ocr_count = extracted.pages.count { |page| page.source == "ocr" }
      extraction.update!(
        status: :succeeded, page_count: extracted.pages.size, native_page_count: extracted.pages.size - ocr_count,
        ocr_page_count: ocr_count, native_engine: extracted.native_engine, ocr_engine: extracted.ocr_engine,
        started_at: extraction.started_at || now, finished_at: now
      )
    end

    def self.record_failure(extraction, error_code)
      extraction.update!(status: :failed, error_code: error_code, finished_at: Time.current)
    end
    private_class_method :succeed, :record_failure
  end
end
