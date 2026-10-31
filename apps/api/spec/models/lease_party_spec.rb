require "rails_helper"

RSpec.describe LeaseParty do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  # Eager: TenantContext does not nest (its `ensure` clears the context), so
  # the lease must not be first created inside another `with_tenant` block.
  let!(:lease) { with_tenant(tenant) { create(:lease, tenant: tenant) } }

  it "rejects an unknown role" do
    party = with_tenant(tenant) { build(:lease_party, lease: lease, role: "tenant") }

    expect(party).not_to be_valid
    expect(party.errors[:role]).to be_present
  end

  it "accepts each counterparty once per lease" do
    party = with_tenant(tenant) { create(:lease_party, lease: lease) }
    duplicate = with_tenant(tenant) { build(:lease_party, lease: lease, counterparty: party.counterparty, role: "guarantor") }

    expect(with_tenant(tenant) { duplicate.valid? }).to be(false)
    expect { with_tenant(tenant) { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "database constraints" do
    it "rejects an unknown role without validations" do
      party = with_tenant(tenant) { create(:lease_party, lease: lease) }

      expect {
        with_tenant(tenant) { LeaseParty.where(id: party.id).update_all(role: "tenant") }
      }.to raise_error(ActiveRecord::StatementInvalid, /lease_parties_role_check/)
    end

    it "rejects a counterparty of another tenant (composite foreign key)" do
      foreign = with_tenant(other_tenant) { create(:counterparty, tenant: other_tenant) }

      expect {
        with_tenant(tenant) do
          LeaseParty.new(tenant: tenant, lease: lease, counterparty_id: foreign.id, role: "lessor").save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_lease_parties_counterparty_same_tenant/)
    end

    it "rejects a lease of another tenant (composite foreign key)" do
      foreign_lease = with_tenant(other_tenant) { create(:lease, tenant: other_tenant) }
      counterparty = with_tenant(tenant) { create(:counterparty, tenant: tenant) }

      expect {
        with_tenant(tenant) do
          LeaseParty.new(tenant: tenant, lease_id: foreign_lease.id, counterparty: counterparty, role: "lessor")
            .save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_lease_parties_lease_same_tenant/)
    end
  end
end
