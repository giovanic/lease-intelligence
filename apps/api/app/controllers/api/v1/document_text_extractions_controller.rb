module Api
  module V1
    # Requests a new text extraction of a version (docs/adr/0016) — after a
    # failure, or to rerun it. Every upload already requests one; this is
    # the manual retry. Requires X-Tenant-Id; a version of another tenant
    # is a 404.
    #
    # POST /api/v1/document_versions/:document_version_id/text_extractions
    #   202 { data: text_extraction }   (owner/admin/manager; status "pending", processed in background)
    #
    # text_extraction = { id, document_version_id, status: pending|running|succeeded|failed,
    #   page_count, native_page_count, ocr_page_count, error_code, started_at, finished_at, created_at }
    # Errors: 401, 403 forbidden/tenant_forbidden, 404 not_found,
    #   409 extraction_in_progress (one is already pending/running).
    class DocumentTextExtractionsController < ApplicationController
      include TenantScoped

      def create
        version = policy_scope(DocumentVersion).find(params[:document_version_id])
        authorize DocumentTextExtraction
        result = DocumentText::RequestExtraction.call(version: version, requested_by: current_user)

        if result.success?
          render json: { data: DocumentTextExtractionSerializer.new(result.value).as_json }, status: :accepted
        else
          render_error(:conflict, "extraction_in_progress", "A text extraction of this version is already in progress.")
        end
      end
    end
  end
end
