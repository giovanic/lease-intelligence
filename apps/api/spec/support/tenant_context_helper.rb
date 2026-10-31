# Every tenant-owned table has FORCE ROW LEVEL SECURITY, including for
# the test-suite's own database role (docs/adr/0003-postgresql-rls.md) —
# there is no superuser shortcut in tests. Any spec that creates or reads
# a Membership/Invitation row must run inside a tenant (and/or user)
# context, exactly like production code would. This helper is the single
# place specs reach for that, so it stays consistent with TenantContext
# itself.
module TenantContextHelper
  def with_tenant(tenant, user: nil, &block)
    TenantContext.activate(tenant: tenant, user: user, &block)
  end

  def with_user_only(user, &block)
    TenantContext.activate(user: user, &block)
  end
end

RSpec.configure do |config|
  config.include TenantContextHelper
end
