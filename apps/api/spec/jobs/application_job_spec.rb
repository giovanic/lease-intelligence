require "rails_helper"

# Tenant-context handling every job inherits (.claude/rules/testing.md:
# fails loudly with no context, succeeds correctly with one).
RSpec.describe ApplicationJob do
  let(:job_class) do
    Class.new(ApplicationJob) do
      def self.name = "ProbeJob"

      # Reports what the database and Current see inside the block.
      def perform(tenant_id)
        within_tenant(tenant_id) do
          { db_tenant: ActiveRecord::Base.connection.select_value("SELECT app_current_tenant_id()::text"),
            current_tenant: Current.tenant&.id,
            visible_properties: Property.pluck(:id) }
        end
      end
    end
  end
  let(:tenant) { create(:tenant) }

  def db_tenant_setting
    ActiveRecord::Base.connection.select_value("SELECT current_setting('app.current_tenant_id', true)")
  end

  it "runs the block in the given tenant's RLS context" do
    own = with_tenant(tenant) { create(:property, tenant: tenant) }
    other_tenant = create(:tenant)
    with_tenant(other_tenant) { create(:property, tenant: other_tenant) }

    result = job_class.perform_now(tenant.id)

    expect(result).to eq(db_tenant: tenant.id, current_tenant: tenant.id, visible_properties: [ own.id ])
  end

  it "leaves no tenant context behind" do
    job_class.perform_now(tenant.id)

    expect(db_tenant_setting).to be_blank
    expect(Current.tenant).to be_nil
  end

  it "fails loudly without a tenant id instead of running with no or a fallback tenant" do
    expect { job_class.perform_now(nil) }.to raise_error(ApplicationJob::TenantContextError, /requires a tenant_id/)
  end

  it "fails loudly for an unknown tenant" do
    expect { job_class.perform_now(SecureRandom.uuid) }.to raise_error(ApplicationJob::TenantContextError, /not found/)
  end

  it "fails loudly for a tenant that is no longer active" do
    tenant.update!(status: "suspended")

    expect { job_class.perform_now(tenant.id) }.to raise_error(ApplicationJob::TenantContextError, /suspended/)
    expect(db_tenant_setting).to be_blank
  end

  it "does not log job arguments" do
    expect(job_class.log_arguments?).to be(false)
  end

  it "is enqueued through the test adapter in specs, not Redis" do
    expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::TestAdapter)
  end
end
