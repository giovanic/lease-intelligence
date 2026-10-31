module Api
  module V1
    # Issues a short-lived link to a version's bytes (docs/adr/0015).
    # Requires X-Tenant-Id; a version of another tenant is a 404.
    #
    # POST /api/v1/document_versions/:document_version_id/download_link
    #   201 { data: { url: "/api/v1/document_files/<token>", expires_at } }
    #   The URL works for 5 minutes, only for this user, only while their
    #   membership is active (see DocumentFilesController).
    # Errors: 401, 403 forbidden/tenant_forbidden, 404 not_found.
    class DocumentDownloadLinksController < ApplicationController
      include TenantScoped

      def create
        version = policy_scope(DocumentVersion).find(params[:document_version_id])
        authorize version, :show?
        link = Documents::DownloadLink.issue(version: version, user: current_user)

        render json: { data: { url: api_v1_document_file_path(token: link.token), expires_at: link.expires_at } },
          status: :created
      end
    end
  end
end
