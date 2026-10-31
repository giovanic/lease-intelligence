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
end
