module Api
  module V1
    # New file versions of a document (docs/adr/0010: a file is never
    # replaced, a correction is a new version). Requires X-Tenant-Id.
    #
    # POST /api/v1/leases/:lease_id/documents/:document_id/versions   multipart/form-data:
    #        version[file]
    #   201 { data: version }   (owner/admin/manager; numbered after the latest one)
    #
    # version: see ContractDocumentsController.
    # Errors: 400 parameter_missing, 401, 403 forbidden/tenant_forbidden, 404 not_found,
    #   415 unsupported_media_type, 422 validation_failed (`file`), 503 storage_unavailable.
    class DocumentVersionsController < ApplicationController
      include TenantScoped
      accepts_multipart_body :create

      def create
        lease = policy_scope(Lease).find(params[:lease_id])
        document = policy_scope(ContractDocument).where(lease_id: lease.id).find(params[:document_id])
        authorize DocumentVersion
        result = Documents::AddVersion.call(
          document: document, uploaded_by: current_user, file: params.require(:version).permit(:file)[:file]
        )

        if result.success?
          render json: { data: DocumentVersionSerializer.new(result.value).as_json }, status: :created
        else
          render_validation_errors(result.error)
        end
      end
    end
  end
end
