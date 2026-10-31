module Identity
  # The memberships through which a user can currently operate: the
  # membership is active AND its tenant is active. This is the single
  # definition used both to list a user's organizations (GET /api/v1/me)
  # and to validate the X-Tenant-Id header (TenantScoped), so the two can
  # never disagree.
  #
  # Runs in a user-only TenantContext: no tenant is active yet, so the
  # rows are visible only through the memberships self-visibility RLS
  # policy (user_id = app_current_user_id()) — a user can never read
  # someone else's memberships here.
  class SelectableMemberships
    def self.all(user)
      TenantContext.activate(user: user) do
        scope(user).includes(:tenant).order("tenants.name").to_a
      end
    end

    def self.find(user, tenant_id)
      TenantContext.activate(user: user) do
        scope(user).includes(:tenant).find_by(tenant_id: tenant_id)
      end
    end

    def self.scope(user)
      user.memberships.active_memberships.joins(:tenant).where(tenants: { status: "active" })
    end
    private_class_method :scope
  end
end
