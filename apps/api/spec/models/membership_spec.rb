require "rails_helper"

RSpec.describe Membership, type: :model do
  let(:tenant) { create(:tenant) }
  let(:user) { create(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:invitation).optional }
  end

  describe "enums" do
    it "accepts the documented roles" do
      with_tenant(tenant, user: user) do
        %w[owner admin manager analyst viewer].each do |role|
          m = build(:membership, tenant: tenant, user: create(:user), role: role)
          expect(m).to be_valid
        end
      end
    end

    it "rejects an undocumented role at the database level" do
      membership = with_tenant(tenant, user: user) { create(:membership, tenant: tenant, user: user) }

      # See the comment in invitation_spec.rb's equivalent test: the
      # DB-raised error must propagate out of `with_tenant`, not be
      # rescued inside it.
      expect {
        with_tenant(tenant, user: user) do
          ActiveRecord::Base.connection.execute(
            "UPDATE memberships SET role = 'superadmin' WHERE id = #{ActiveRecord::Base.connection.quote(membership.id)}"
          )
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /memberships_role_check/)
    end
  end

  describe "validations" do
    it "requires a user to have only one membership per tenant" do
      with_tenant(tenant, user: user) do
        create(:membership, tenant: tenant, user: user)
        duplicate = build(:membership, tenant: tenant, user: user)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:user_id]).to be_present
      end
    end

    it "rejects a membership whose invitation belongs to a different tenant" do
      other_tenant = create(:tenant)
      other_invitation = with_tenant(other_tenant) { create(:invitation, tenant: other_tenant) }

      with_tenant(tenant, user: user) do
        membership = build(:membership, tenant: tenant, user: user, invitation: other_invitation)
        expect(membership).not_to be_valid
        expect(membership.errors[:invitation]).to be_present
      end
    end
  end

  describe "database enforcement of the same-tenant invitation rule" do
    it "rejects the mismatch even when Rails-level validation is bypassed" do
      other_tenant = create(:tenant)
      other_invitation = with_tenant(other_tenant) { create(:invitation, tenant: other_tenant) }

      expect {
        with_tenant(tenant, user: user) do
          ActiveRecord::Base.connection.execute(<<~SQL)
            INSERT INTO memberships (id, tenant_id, user_id, invitation_id, role, status, created_at, updated_at)
            VALUES (
              gen_random_uuid(),
              #{ActiveRecord::Base.connection.quote(tenant.id)},
              #{ActiveRecord::Base.connection.quote(user.id)},
              #{ActiveRecord::Base.connection.quote(other_invitation.id)},
              'owner', 'active', now(), now()
            )
          SQL
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
