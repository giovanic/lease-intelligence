require "rails_helper"

# Organization settings (docs/adr/0018): any active member reads, only
# owners/admins change, never another organization's settings.
RSpec.describe OrganizationSettingsPolicy do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }

  def context_for(role, status: "active")
    membership = with_tenant(tenant) { create(:membership, tenant: tenant, user: user, role: role, status: status) }
    AuthorizationContext.new(user: user, membership: membership)
  end

  %w[owner admin].each do |role|
    it "lets an active #{role} read and change the settings" do
      policy = described_class.new(context_for(role), tenant)

      expect([ policy.show?, policy.update? ]).to eq([ true, true ])
    end
  end

  %w[manager analyst viewer].each do |role|
    it "lets an active #{role} read but not change the settings" do
      policy = described_class.new(context_for(role), tenant)

      expect([ policy.show?, policy.update? ]).to eq([ true, false ])
    end
  end

  it "denies another organization's settings, even to an owner" do
    policy = described_class.new(context_for("owner"), other_tenant)

    expect([ policy.show?, policy.update? ]).to eq([ false, false ])
  end

  it "denies everything to a suspended membership and without a membership" do
    [ context_for("owner", status: "suspended"), AuthorizationContext.new(user: user) ].each do |context|
      policy = described_class.new(context, tenant)

      expect([ policy.show?, policy.update? ]).to eq([ false, false ])
    end
  end
end
