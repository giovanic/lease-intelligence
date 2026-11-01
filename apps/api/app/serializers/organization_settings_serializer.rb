# Explicit JSON shape for the current organization's settings
# (docs/adr/0018). `ai_provider` is the deployment's configured LLM (null
# when none): shown so whoever turns AI extraction on sees whether the
# contracts would leave our infrastructure (`external`).
class OrganizationSettingsSerializer
  def initialize(tenant, provider:)
    @tenant = tenant
    @provider = provider
  end

  def as_json(*)
    changed_by = @tenant.ai_extraction_changed_by
    {
      ai_extraction_enabled: @tenant.ai_extraction_enabled,
      ai_extraction_changed_at: @tenant.ai_extraction_changed_at,
      ai_extraction_changed_by: changed_by && { id: changed_by.id, full_name: changed_by.full_name },
      ai_provider: @provider && { name: @provider.name, model: @provider.model, external: @provider.external? }
    }
  end
end
