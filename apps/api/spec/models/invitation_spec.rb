require "rails_helper"

RSpec.describe Invitation, type: :model do
  let(:tenant) { create(:tenant) }
  let(:inviter) { create(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:invited_by).class_name("User") }
    it { is_expected.to have_one(:membership) }
  end

  describe "validations" do
    it "requires a valid email format" do
      with_tenant(tenant, user: inviter) do
        invitation = build(:invitation, tenant: tenant, invited_by: inviter, email: "not-an-email")
        expect(invitation).not_to be_valid
      end
    end

    it "downcases the email before validation" do
      with_tenant(tenant, user: inviter) do
        invitation = build(:invitation, tenant: tenant, invited_by: inviter, email: "Mixed.Case@Example.com")
        invitation.valid?
        expect(invitation.email).to eq("mixed.case@example.com")
      end
    end

    it "prevents a second pending invitation to the same email in the same tenant" do
      with_tenant(tenant, user: inviter) do
        create(:invitation, tenant: tenant, invited_by: inviter, email: "dup@example.com")
        duplicate = build(:invitation, tenant: tenant, invited_by: inviter, email: "dup@example.com")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:email]).to be_present
      end
    end

    it "allows re-inviting the same email once the prior invitation is no longer pending" do
      with_tenant(tenant, user: inviter) do
        first = create(:invitation, tenant: tenant, invited_by: inviter, email: "retry@example.com")
        first.update!(status: "revoked")

        second = build(:invitation, tenant: tenant, invited_by: inviter, email: "retry@example.com")
        expect(second).to be_valid
      end
    end
  end

  describe "#expired?" do
    it "is true once expires_at is in the past" do
      with_tenant(tenant, user: inviter) do
        invitation = create(:invitation, tenant: tenant, invited_by: inviter, expires_at: 1.day.ago)
        expect(invitation).to be_expired
      end
    end

    it "is false while expires_at is in the future" do
      with_tenant(tenant, user: inviter) do
        invitation = create(:invitation, tenant: tenant, invited_by: inviter, expires_at: 1.day.from_now)
        expect(invitation).not_to be_expired
      end
    end
  end

  describe "#token" do
    it "is generated automatically and is unique" do
      with_tenant(tenant, user: inviter) do
        invitation = create(:invitation, tenant: tenant, invited_by: inviter)
        expect(invitation.token).to be_present
      end
    end
  end

  describe "database constraints" do
    it "rejects an undocumented status at the database level" do
      invitation = with_tenant(tenant, user: inviter) { create(:invitation, tenant: tenant, invited_by: inviter) }

      # The DB-raised error must propagate out of `with_tenant` itself
      # (not be swallowed inside it) so TenantContext's `requires_new:
      # true` savepoint can roll back cleanly on the way out — rescuing
      # it inside the block would leave that subtransaction aborted.
      expect {
        with_tenant(tenant, user: inviter) do
          ActiveRecord::Base.connection.execute(
            "UPDATE invitations SET status = 'not_real' WHERE id = #{ActiveRecord::Base.connection.quote(invitation.id)}"
          )
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /invitations_status_check/)
    end
  end
end
