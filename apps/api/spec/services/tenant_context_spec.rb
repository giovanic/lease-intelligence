require "rails_helper"

RSpec.describe TenantContext do
  let(:tenant) { create(:tenant) }
  let(:user) { create(:user) }

  def current_setting(name)
    ActiveRecord::Base.connection.select_value(
      "SELECT current_setting(#{ActiveRecord::Base.connection.quote(name)}, true)"
    )
  end

  it "sets Current.tenant and Current.user for the duration of the block" do
    described_class.activate(tenant: tenant, user: user) do
      expect(Current.tenant).to eq(tenant)
      expect(Current.user).to eq(user)
    end
  end

  it "clears Current.tenant and Current.user after the block" do
    described_class.activate(tenant: tenant, user: user) { nil }

    expect(Current.tenant).to be_nil
    expect(Current.user).to be_nil
  end

  it "sets the underlying Postgres session settings that RLS policies read" do
    described_class.activate(tenant: tenant, user: user) do
      expect(current_setting("app.current_tenant_id")).to eq(tenant.id)
      expect(current_setting("app.current_user_id")).to eq(user.id)
    end
  end

  it "does not leak the session setting past the transaction (SET LOCAL semantics)" do
    described_class.activate(tenant: tenant, user: user) { nil }

    expect(current_setting("app.current_tenant_id")).to be_blank
  end

  it "supports activating with only a user (no tenant), for the org-listing bootstrap" do
    described_class.activate(user: user) do
      expect(current_setting("app.current_tenant_id")).to be_blank
      expect(current_setting("app.current_user_id")).to eq(user.id)
    end
  end

  it "requires a block" do
    expect { described_class.activate(tenant: tenant) }.to raise_error(ArgumentError)
  end

  # Regression: during a request Rails enables the query cache, and an
  # identical `SELECT set_config(...)` was served from the cache instead of
  # being executed — so switching A -> B -> A stayed on B, and the reset in
  # `ensure` was skipped, leaving the tenant active after the block.
  describe "with the query cache enabled (as inside every request)" do
    around { |example| ActiveRecord::Base.cache { example.run } }

    def db_setting(name)
      ActiveRecord::Base.connection.uncached do
        ActiveRecord::Base.connection.select_value("SELECT current_setting('#{name}', true)")
      end
    end

    it "really switches context when the same tenant is activated again" do
      other_tenant = create(:tenant)

      described_class.activate(tenant: tenant, user: user) { nil }
      described_class.activate(tenant: other_tenant, user: user) { nil }
      described_class.activate(tenant: tenant, user: user) do
        expect(db_setting("app.current_tenant_id")).to eq(tenant.id)
        expect(db_setting("app.current_user_id")).to eq(user.id)
      end
    end

    it "really clears the context after the block" do
      described_class.activate(user: user) { nil }
      described_class.activate(tenant: tenant, user: user) { nil }

      expect(db_setting("app.current_tenant_id")).to be_blank
      expect(db_setting("app.current_user_id")).to be_blank
    end
  end
end
