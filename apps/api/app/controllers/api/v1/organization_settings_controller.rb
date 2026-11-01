module Api
  module V1
    # Settings of the current organization (docs/adr/0018) — for now, the
    # consent for AI field extraction. Requires X-Tenant-Id; always acts on
    # that (membership-validated) tenant, never on an id from the body.
    #
    # GET   /api/v1/organization_settings
    #   200 { data: settings }   (any active member)
    # PATCH /api/v1/organization_settings   { organization_settings: { ai_extraction_enabled: true|false } }
    #   200 { data: settings }   (owner/admin)
    #
    # settings = { ai_extraction_enabled, ai_extraction_changed_at, ai_extraction_changed_by: { id, full_name } | null,
    #   ai_provider: { name: "ollama"|"anthropic", model, external: bool } | null }
    # Errors: 400 parameter_missing, 401, 403 forbidden/tenant_forbidden,
    #   422 validation_failed (`ai_extraction_enabled` not a JSON boolean).
    class OrganizationSettingsController < ApplicationController
      include TenantScoped

      def show
        authorize tenant, policy_class: OrganizationSettingsPolicy
        render_settings
      end

      def update
        authorize tenant, policy_class: OrganizationSettingsPolicy
        enabled = params.require(:organization_settings).permit(:ai_extraction_enabled)[:ai_extraction_enabled]
        result = Organizations::UpdateAiConsent.call(tenant: tenant, enabled: enabled, changed_by: current_user)
        return render_validation_errors(result.error) if result.failure?

        render_settings
      end

      private

      def tenant
        current_membership.tenant
      end

      def render_settings
        render json: { data: OrganizationSettingsSerializer.new(tenant, provider: Llm.provider).as_json }
      end
    end
  end
end
