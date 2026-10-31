# The role is informative for the SPA's UX only; the backend always
# re-derives it from the database (ADR-0005, ADR-0013).
class MembershipSerializer
  def initialize(membership)
    @membership = membership
  end

  def as_json(*)
    tenant = @membership.tenant
    {
      id: @membership.id,
      role: @membership.role,
      status: @membership.status,
      tenant: { id: tenant.id, name: tenant.name, slug: tenant.slug }
    }
  end
end
