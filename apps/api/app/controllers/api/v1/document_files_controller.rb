module Api
  module V1
    # Serves a document version's bytes for a link issued by
    # DocumentDownloadLinksController (docs/adr/0015). Not TenantScoped: a
    # browser navigation (new tab, <iframe>) cannot send X-Tenant-Id, so the
    # tenant comes from the signed token — and is honored only after the
    # same server-side checks TenantScoped does:
    #
    # 1. the session cookie (authenticate_user!);
    # 2. a valid, unexpired token issued to *this* user;
    # 3. an active membership in an active tenant (SelectableMemberships);
    # 4. the version loaded under RLS in that tenant, authorized by Pundit.
    #
    # GET /api/v1/document_files/:token
    #   200 the file (Content-Disposition: inline, verified Content-Type,
    #       Cache-Control: private, no-store)
    # Errors: 401; 404 not_found for any token/membership/version problem
    #   (no oracle for which part failed); 503 storage_unavailable.
    class DocumentFilesController < ApplicationController
      before_action :authenticate_user!
      before_action :resolve_download_membership

      def show
        TenantContext.activate(tenant: current_membership.tenant, user: current_user) do
          version = policy_scope(DocumentVersion).find(@claims["version_id"])
          authorize version, :show?
          data = Documents::FileStore.download(version.storage_key)

          send_data data, type: version.content_type, disposition: "inline"
          # Set by hand rather than through send_data's `filename:`, which
          # Rails logs at info level ("Sent data <filename>") — original
          # filenames often carry personal data (.claude/rules/security.md).
          response.headers["Content-Disposition"] =
            ActionDispatch::Http::ContentDisposition.format(disposition: "inline", filename: version.original_filename)
          response.headers["Cache-Control"] = "private, no-store"
        end
      end

      private

      attr_reader :current_membership

      def resolve_download_membership
        @claims = Documents::DownloadLink.resolve(params[:token])
        if @claims && @claims["user_id"] == current_user.id
          @current_membership = Identity::SelectableMemberships.find(current_user, @claims["tenant_id"])
        end
        return if @current_membership

        render_error(:not_found, "not_found", "Resource not found.")
      end
    end
  end
end
