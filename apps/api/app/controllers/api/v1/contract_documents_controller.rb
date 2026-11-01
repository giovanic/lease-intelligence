module Api
  module V1
    # Documents of a lease (docs/domain/documents.md). All actions require
    # the X-Tenant-Id header (TenantScoped); a lease or document of another
    # tenant is a 404, exactly like a nonexistent one.
    #
    # GET  /api/v1/leases/:lease_id/documents?page=&per_page=
    #   200 { data: [document, ...], meta: { page, per_page, total_count, total_pages } }
    # GET  /api/v1/leases/:lease_id/documents/:id
    #   200 { data: document }
    # POST /api/v1/leases/:lease_id/documents   multipart/form-data:
    #        document[kind]=original_contract|amendment|other, document[title], document[file]
    #   201 { data: document }   (owner/admin/manager; creates version 1)
    #
    # document = { id, lease_id, kind, title, versions: [version, ...] (newest first),
    #   created_at, updated_at }
    # version = { id, contract_document_id, version_number, original_filename, content_type,
    #   byte_size, sha256, uploaded_by: { id, full_name }, text_extraction: text_extraction | null,
    #   extraction_run: run | null, created_at }
    # text_extraction: the latest attempt, see DocumentTextExtractionsController (every upload
    #   requests one, so a new version starts with status "pending").
    # extraction_run: the latest AI field extraction run (summary), see ExtractionRunsController
    #   (requested when the text extraction succeeds, if an LLM provider is configured).
    # Errors: 400 parameter_missing/invalid_parameter, 401, 403 forbidden/tenant_forbidden,
    #   404 not_found, 415 unsupported_media_type, 422 validation_failed (`file`: blank, empty,
    #   too large, not PDF/JPEG/PNG/TIFF, already uploaded; `kind`: second original contract),
    #   503 storage_unavailable.
    class ContractDocumentsController < ApplicationController
      include TenantScoped
      include Paginated
      accepts_multipart_body :create

      def index
        lease = find_lease
        authorize ContractDocument
        relation = policy_scope(ContractDocument).where(lease_id: lease.id)
          .includes(versions: %i[uploaded_by latest_text_extraction latest_extraction_run]).order(:created_at, :id)
        documents, meta = paginate(relation)

        render json: { data: documents.map { |document| ContractDocumentSerializer.new(document).as_json }, meta: meta }
      end

      def show
        document = policy_scope(ContractDocument).where(lease_id: find_lease.id)
          .includes(versions: %i[uploaded_by latest_text_extraction latest_extraction_run]).find(params[:id])
        authorize document

        render json: { data: ContractDocumentSerializer.new(document).as_json }
      end

      def create
        lease = find_lease
        authorize ContractDocument
        result = Documents::CreateDocument.call(
          lease: lease, uploaded_by: current_user, attributes: document_params.slice(:kind, :title),
          file: document_params[:file]
        )

        if result.success?
          render json: { data: ContractDocumentSerializer.new(result.value).as_json }, status: :created
        else
          render_validation_errors(result.error)
        end
      end

      private

      def find_lease
        policy_scope(Lease).find(params[:lease_id])
      end

      def document_params
        params.require(:document).permit(:kind, :title, :file)
      end
    end
  end
end
