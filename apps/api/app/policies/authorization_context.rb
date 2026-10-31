# What every Pundit policy authorizes against: the authenticated user and,
# on tenant-scoped requests, their active membership in the current tenant
# (resolved by TenantScoped from server-side data, never from client input).
AuthorizationContext = Data.define(:user, :membership) do
  def initialize(user:, membership: nil)
    super
  end
end
