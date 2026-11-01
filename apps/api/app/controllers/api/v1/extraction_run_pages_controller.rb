module Api
  module V1
    # The full text of one page of the text an extraction run read
    # (docs/adr/0019), for highlighting evidence on the review screen.
    # Contract content: the same audience that can download the file (any
    # active member, ExtractionRunPolicy#show?). Requires X-Tenant-Id; a run
    # of another tenant is a 404.
    #
    # GET /api/v1/extraction_runs/:extraction_run_id/pages/:page_number
    #   200 { data: { page_number, source: native|ocr, text } }
    # Errors: 401, 403 forbidden/tenant_forbidden, 404 not_found (run or page).
    class ExtractionRunPagesController < ApplicationController
      include TenantScoped

      def show
        run = policy_scope(ExtractionRun).find(params[:extraction_run_id])
        authorize run, :show?
        page = run.text_extraction.pages.find_by!(page_number: params[:page_number])
        render json: { data: DocumentTextPageSerializer.new(page).as_json }
      end
    end
  end
end
