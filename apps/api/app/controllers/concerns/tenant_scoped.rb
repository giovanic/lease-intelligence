# Resolves "which tenant is this request operating as" and runs the whole
# action inside that tenant's RLS context
# (docs/adr/0013-spa-session-auth-and-tenant-selection.md,
# .claude/rules/multi-tenancy.md).
#
# The `X-Tenant-Id` header is only a *request*: it is honored solely when
# the authenticated user has an active membership in an active tenant
# with that id, looked up server-side. Every failure other than a missing
# header gets the same 403, so the endpoint is not an oracle for which
# tenant ids exist.
#
# The action runs inside TenantContext.activate — one transaction with
# `SET LOCAL`, cleared in `ensure` — so nothing survives on the pooled
# connection after the request.
module TenantScoped
  extend ActiveSupport::Concern

  TENANT_HEADER = "X-Tenant-Id".freeze
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  included do
    # Resolution is a before_action (not part of the around_action) so a
    # rejection halts the chain — after_actions such as verify_authorized
    # are skipped only for halting *before* callbacks.
    before_action :authenticate_user!
    before_action :resolve_current_membership
    around_action :run_in_tenant_context
  end

  private

  attr_reader :current_membership

  def resolve_current_membership
    requested_tenant_id = request.headers[TENANT_HEADER]
    if requested_tenant_id.blank?
      return render_error(:bad_request, "tenant_required", "The #{TENANT_HEADER} header is required.")
    end

    @current_membership = if UUID_FORMAT.match?(requested_tenant_id)
      Identity::SelectableMemberships.find(current_user, requested_tenant_id)
    end
    return if @current_membership

    render_error(:forbidden, "tenant_forbidden", "You do not have access to this organization.")
  end

  def run_in_tenant_context(&action)
    TenantContext.activate(tenant: current_membership.tenant, user: current_user, &action)
  end
end
