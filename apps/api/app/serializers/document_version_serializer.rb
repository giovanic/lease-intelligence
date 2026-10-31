# Explicit JSON shape for a DocumentVersion. The storage key is internal
# and never leaves the API (docs/adr/0015): the bytes are reached only
# through POST /api/v1/document_versions/:id/download_link.
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
      created_at: @version.created_at
    }
  end
end
