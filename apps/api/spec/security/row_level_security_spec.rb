require "rails_helper"

# The raw-SQL-level layer of the three-layer tenant isolation test
# described in docs/runbooks/testing.md: this proves PostgreSQL itself
# refuses cross-tenant rows for the role the application actually
# connects as (lease_intelligence — non-superuser, no BYPASSRLS, see
# config/database.yml), independent of any ActiveRecord/Rails-level
# authorization. There are no controllers/policies yet in this
# data-layer phase, so the "request-level" layer of the three described
# in the runbook does not exist yet; this is the database-level proof.
RSpec.describe "Row-Level Security", type: :model do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  describe "memberships" do
    it "denies an insert with no tenant context" do
      membership = build(:membership, tenant: tenant_a, user: user_a)
      expect { membership.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "denies an insert whose tenant_id does not match the active tenant context" do
      # The raise must propagate out of `with_tenant` itself so its
      # `requires_new: true` savepoint rolls back cleanly on the way out
      # (see TenantContext's comment) — rescuing it inside would leave
      # that subtransaction aborted for whatever runs next.
      expect {
        with_tenant(tenant_a, user: user_a) do
          mismatched = build(:membership, tenant: tenant_b, user: user_a)
          mismatched.save!(validate: false)
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "only returns the active tenant's rows when both tenants have memberships" do
      membership_a = with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }
      membership_b = with_tenant(tenant_b, user: user_b) { create(:membership, tenant: tenant_b, user: user_b) }

      with_tenant(tenant_a, user: user_a) do
        visible = Membership.pluck(:id)
        expect(visible).to contain_exactly(membership_a.id)
        expect(visible).not_to include(membership_b.id)
      end
    end

    it "lets a user see their own membership rows with no active tenant context (bootstrap)" do
      membership_a = with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }
      with_tenant(tenant_b, user: user_b) { create(:membership, tenant: tenant_b, user: user_b) }

      with_user_only(user_a) do
        visible = Membership.pluck(:id)
        expect(visible).to eq([ membership_a.id ])
      end
    end

    it "returns nothing at all with neither tenant nor user context" do
      with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }

      expect(Membership.count).to eq(0)
    end
  end

  describe "invitations" do
    it "denies an insert with no tenant context" do
      invitation = build(:invitation, tenant: tenant_a, invited_by: user_a)
      expect { invitation.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "only returns the active tenant's invitations" do
      invitation_a = with_tenant(tenant_a, user: user_a) { create(:invitation, tenant: tenant_a, invited_by: user_a) }
      invitation_b = with_tenant(tenant_b, user: user_b) { create(:invitation, tenant: tenant_b, invited_by: user_b) }

      with_tenant(tenant_a, user: user_a) do
        visible = Invitation.pluck(:id)
        expect(visible).to contain_exactly(invitation_a.id)
        expect(visible).not_to include(invitation_b.id)
      end
    end
  end
end
