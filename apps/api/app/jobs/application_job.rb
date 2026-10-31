# Base for every job (docs/adr/0006-background-processing-sidekiq.md,
# docs/architecture/background-processing.md).
#
# Rules every subclass follows:
# - Arguments are primitive ids, never records, document text, personal
#   data or credentials: they are stored in Redis in plain text.
# - A job touching tenant-owned data receives the tenant id and wraps
#   that work in `within_tenant`. Jobs never inherit a request's tenant
#   context, and there is no fallback tenant.
# - Jobs are idempotent: running twice must not double-create or
#   double-charge a provider.
class ApplicationJob < ActiveJob::Base
  # The job cannot establish the tenant context it was given. Raised, not
  # swallowed: the job fails visibly (Sidekiq logs it, retries with
  # backoff, then moves it to the dead set).
  class TenantContextError < StandardError; end

  # Arguments are ids only, but keep them out of the logs regardless.
  self.log_arguments = false

  private

  # Runs the block in the RLS context of an active tenant, inside one
  # transaction (TenantContext). Keep slow work — OCR/LLM provider calls —
  # outside the block: use several short `within_tenant` calls around it
  # rather than holding a transaction open for the whole call.
  def within_tenant(tenant_id, &block)
    raise TenantContextError, "#{self.class.name} requires a tenant_id" if tenant_id.blank?

    # tenants has no RLS (it is the tenancy anchor), so this lookup
    # works before any context is active.
    tenant = Tenant.find_by(id: tenant_id)
    raise TenantContextError, "#{self.class.name}: tenant #{tenant_id} not found" if tenant.nil?
    raise TenantContextError, "#{self.class.name}: tenant #{tenant_id} is #{tenant.status}" unless tenant.active?

    TenantContext.activate(tenant: tenant, &block)
  end
end
