module Organizations
  # Turns AI field extraction on or off for one organization
  # (docs/adr/0018), recording who changed it and when. The caller passes
  # the tenant TenantScoped resolved — never one looked up from input
  # (`tenants` has no RLS). Authorization (owner/admin) is the controller's,
  # through OrganizationSettingsPolicy. Turning it off does not touch runs
  # already finished; queued ones fail as `ai_disabled` when they start.
  #
  # success(Tenant) | failure(errors) when `enabled` is not a boolean.
  class UpdateAiConsent
    def self.call(tenant:, enabled:, changed_by:)
      return ServiceResult.failure("ai_extraction_enabled" => [ "must be true or false" ]) unless [ true, false ].include?(enabled)
      return ServiceResult.success(tenant) if tenant.ai_extraction_enabled == enabled

      tenant.update!(ai_extraction_enabled: enabled, ai_extraction_changed_at: Time.current,
        ai_extraction_changed_by: changed_by)
      ServiceResult.success(tenant)
    end
  end
end
