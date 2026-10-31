# Explicit JSON shape for a DocumentTextExtraction: status and counts only.
# The extracted text is contract content and is not part of the API in
# this phase (docs/adr/0016 "API exposure"); neither are the engine
# versions, which are internal.
class DocumentTextExtractionSerializer
  def initialize(extraction)
    @extraction = extraction
  end

  def as_json(*)
    {
      id: @extraction.id,
      document_version_id: @extraction.document_version_id,
      status: @extraction.status,
      page_count: @extraction.page_count,
      native_page_count: @extraction.native_page_count,
      ocr_page_count: @extraction.ocr_page_count,
      error_code: @extraction.error_code,
      started_at: @extraction.started_at,
      finished_at: @extraction.finished_at,
      created_at: @extraction.created_at
    }
  end
end
