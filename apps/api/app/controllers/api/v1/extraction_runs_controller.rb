module Api
  module V1
    # AI field extraction runs of a version (docs/adr/0017). Every successful
    # text extraction already requests one; `create` is the manual request
    # (after a failure, or to rerun it). Requires X-Tenant-Id; a version or
    # run of another tenant is a 404.
    #
    # POST /api/v1/document_versions/:document_version_id/extraction_runs
    #   202 { data: run }   (owner/admin/manager; status "pending", processed in background)
    # GET  /api/v1/extraction_runs/:id
    #   200 { data: run + fields }   (any active member)
    #
    # run = { id, document_version_id, status: pending|running|succeeded|failed, field_count,
    #   rejected_field_count, error_code, started_at, finished_at, created_at }
    # fields (GET only, at most ~75 by the catalog caps, so not paginated) =
    #   [{ id, key, value_type: date|integer|money|option|text|party, value, evidence: [
    #      { id, page_number, source: native|ocr, start_offset, end_offset, snippet }],
    #      review: review_decision | null (latest), review_count }]
    # review_summary (GET only) = { approved, corrected, rejected, pending } (current state per field)
    # document_version (GET only) = { id, contract_document_id, version_number, original_filename, content_type }
    # review_decision: see ReviewDecisionsController.
    # value by value_type: { date: "YYYY-MM-DD" } | { integer: n } | { amount: "12000.00", currency: "BRL" }
    #   | { option: "igp_m" } | { text: "..." } | { name: "...", tax_id: "digits" | null }
    # Every field is an unreviewed AI candidate, never an approved fact.
    # Errors: 401, 403 forbidden/tenant_forbidden, 404 not_found,
    #   409 extraction_in_progress (one is already pending/running),
    #   422 extraction_disabled (the organization has not turned AI extraction on, docs/adr/0018),
    #   422 text_not_ready (no succeeded text extraction for the version),
    #   503 extraction_unavailable (no LLM provider configured).
    class ExtractionRunsController < ApplicationController
      include TenantScoped

      def show
        run = policy_scope(ExtractionRun).includes(:document_version,
          fields: [ { evidence_references: :text_page }, { review_decisions: :reviewed_by } ]).find(params[:id])
        authorize run
        render json: { data: ExtractionRunSerializer.new(run, with_fields: true).as_json }
      end

      def create
        version = policy_scope(DocumentVersion).find(params[:document_version_id])
        authorize ExtractionRun
        result = FieldExtraction::RequestRun.call(version: version, requested_by: current_user)
        return render json: { data: ExtractionRunSerializer.new(result.value).as_json }, status: :accepted if result.success?

        case result.error
        when "in_progress"
          render_error(:conflict, "extraction_in_progress", "A field extraction of this version is already in progress.")
        when "disabled"
          render_error(:unprocessable_content, "extraction_disabled",
            "AI field extraction is turned off for this organization.")
        when "text_not_ready"
          render_error(:unprocessable_content, "text_not_ready", "The text of this version has not been extracted yet.")
        else
          render_error(:service_unavailable, "extraction_unavailable", "AI field extraction is not configured.")
        end
      end
    end
  end
end
