require "rails_helper"

RSpec.describe Identity::SelectableMemberships do
  let(:user) { create(:user) }
  let(:active_tenant) { create(:tenant, name: "B Active") }
  let(:other_active_tenant) { create(:tenant, name: "A Active") }
  let(:suspended_tenant) { create(:tenant, status: "suspended") }

  let!(:selectable) { with_tenant(active_tenant) { create(:membership, tenant: active_tenant, user: user) } }
  let!(:selectable_2) { with_tenant(other_active_tenant) { create(:membership, tenant: other_active_tenant, user: user) } }

  before do
    with_tenant(suspended_tenant) { create(:membership, tenant: suspended_tenant, user: user) }
    with_tenant(active_tenant) { create(:membership, tenant: active_tenant, user: create(:user)) }
  end

  describe ".all" do
    it "returns only the user's active memberships in active tenants, ordered by tenant name" do
      expect(described_class.all(user)).to eq([ selectable_2, selectable ])
    end

    it "leaves no RLS context behind" do
      described_class.all(user)

      expect(Membership.count).to eq(0)
    end
  end

  describe ".find" do
    it "finds the membership for a selectable tenant" do
      expect(described_class.find(user, active_tenant.id)).to eq(selectable)
    end

    it "returns nil for a suspended tenant" do
      expect(described_class.find(user, suspended_tenant.id)).to be_nil
    end

    it "returns nil for a tenant the user does not belong to" do
      stranger_tenant = create(:tenant)

      expect(described_class.find(user, stranger_tenant.id)).to be_nil
    end
  end
end
