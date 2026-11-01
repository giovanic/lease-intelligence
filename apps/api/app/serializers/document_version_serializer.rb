# Explicit JSON shape for a DocumentVersion. The storage key is internal
# and never leaves the API (docs/adr/0015): the bytes are reached only
# through POST /api/v1/document_versions/:id/download_link. `text_extraction`
# is the latest text extraction attempt (docs/adr/0016), or null;
# `extraction_run` the latest AI field extraction run (docs/adr/0017), or null.
class DocumentVersionSerializer
  def initialize(version)
    @version = version
  end

  def as_json(*)
    {
      id: @version.id,
      contract_document_id: @version.contract_document_id,
      version_number: @version.version_number,
      original_filename: @version.original_filename,
      content_type: @version.content_type,
      byte_size: @version.byte_size,
      sha256: @version.sha256,
      uploaded_by: { id: @version.uploaded_by.id, full_name: @version.uploaded_by.full_name },
      text_extraction: @version.latest_text_extraction&.then { |extraction| DocumentTextExtractionSerializer.new(extraction).as_json },
      extraction_run: @version.latest_extraction_run&.then { |run| ExtractionRunSerializer.new(run).as_json },
      created_at: @version.created_at
    }
  end
end
