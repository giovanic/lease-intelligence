module Portfolio
  # Registers a property in the given tenant's portfolio. The tenant comes
  # from the caller's server-resolved membership (TenantScoped), never from
  # request input — `attributes` must not carry tenant_id. Runs inside the
  # request's TenantContext, so RLS also rejects any other tenant.
  # Returns the Property on success, its ActiveModel::Errors on failure.
  class CreateProperty
    def self.call(tenant:, attributes:)
      property = Property.new(attributes)
      property.tenant = tenant

      property.save ? ServiceResult.success(property) : ServiceResult.failure(property.errors)
    end
  end
end
