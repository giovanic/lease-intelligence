module Api
  module V1
    # Human decisions on AI-extracted fields (docs/adr/0012, docs/adr/0019).
    # Append-only: a new decision supersedes the previous one, which stays
    # in history. Requires X-Tenant-Id; a field of another tenant is a 404.
    #
    # POST /api/v1/extracted_fields/:extracted_field_id/review_decisions
    #   { review_decision: { decision: approved|corrected|rejected, value?: {...}, reason?: "..." } }
    #   201 { data: review_decision }   (owner/admin/manager/analyst)
    #
    # `value` only with `corrected`, shaped like the field's value in the run JSON
    # ({ date } | { integer } | { amount, currency } | { option } | { text } | { name, tax_id }).
    # review_decision = { id, extracted_field_id, decision, value (null unless corrected), reason,
    #   reviewed_by: { id, full_name }, created_at }
    # Errors: 400 parameter_missing, 401, 403 forbidden/tenant_forbidden, 404 not_found,
    #   409 stale_run (the field belongs to an older run of its version),
    #   422 validation_failed (`decision`, `value`, `reason`).
    class ReviewDecisionsController < ApplicationController
      include TenantScoped

      def create
        field = policy_scope(ExtractedField).find(params[:extracted_field_id])
        authorize ReviewDecision
        attributes = params.require(:review_decision).permit(:decision, :reason, value: {})
        result = ContractReview::RecordDecision.call(field: field, decision: attributes[:decision],
          value: attributes[:value]&.to_h, reason: attributes[:reason], reviewed_by: current_user)

        if result.success?
          render json: { data: ReviewDecisionSerializer.new(result.value).as_json }, status: :created
        elsif result.error == "stale_run"
          render_error(:conflict, "stale_run", "This field belongs to an older extraction run of its version.")
        else
          render_validation_errors(result.error)
        end
      end
    end
  end
end
