require "rails_helper"
require "pundit/rspec"

# Policy layer of the three-layer tenant isolation test.
RSpec.describe MembershipPolicy do
  subject { described_class }

  let(:user) { create(:user) }
  let(:tenant) { create(:tenant) }
  let(:membership) { with_tenant(tenant) { create(:membership, tenant: tenant, user: user) } }

  permissions :show? do
    it "allows the caller's own current membership" do
      expect(subject).to permit(AuthorizationContext.new(user: user, membership: membership), membership)
    end

    it "denies a membership other than the current one (e.g. another tenant's)" do
      other_tenant = create(:tenant)
      other = with_tenant(other_tenant) { create(:membership, tenant: other_tenant, user: user) }

      expect(subject).not_to permit(AuthorizationContext.new(user: user, membership: membership), other)
    end

    it "denies another user's membership" do
      other = with_tenant(tenant) { create(:membership, tenant: tenant, user: create(:user)) }

      expect(subject).not_to permit(AuthorizationContext.new(user: user, membership: other), other)
    end

    it "denies when there is no tenant context (no membership)" do
      expect(subject).not_to permit(AuthorizationContext.new(user: user), membership)
    end

    it "denies a suspended membership" do
      membership.status = "suspended"

      expect(subject).not_to permit(AuthorizationContext.new(user: user, membership: membership), membership)
    end
  end

  it "refuses to evaluate without an authenticated user" do
    expect { described_class.new(AuthorizationContext.new(user: nil), membership) }
      .to raise_error(Pundit::NotAuthorizedError)
  end
end
