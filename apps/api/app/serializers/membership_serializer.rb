# The role is informative for the SPA's UX only; the backend always
# re-derives it from the database (ADR-0005, ADR-0013). So is
# `ai_extraction_enabled` (docs/adr/0018): it only decides what the SPA
# offers; FieldExtraction::RequestRun checks the tenant row itself.
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
      tenant: { id: tenant.id, name: tenant.name, slug: tenant.slug, ai_extraction_enabled: tenant.ai_extraction_enabled }
    }
  end
end
