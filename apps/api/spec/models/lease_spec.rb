require "rails_helper"

RSpec.describe Lease do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }

  def build_lease(**attributes)
    build(:lease, tenant: tenant, **attributes)
  end

  it "normalizes title, notes and code" do
    lease = build_lease(title: "  Loja Centro  ", notes: "   ", code: " loc-01 ")

    expect([ lease.title, lease.notes, lease.code ]).to eq([ "Loja Centro", nil, "LOC-01" ])
  end

  it "defaults to draft" do
    expect(Lease.new.status).to eq("draft")
  end

  it "rejects an unknown status" do
    lease = build_lease(status: "cancelled")

    expect(lease).not_to be_valid
    expect(lease.errors[:status]).to be_present
  end

  it "requires a title" do
    expect(build_lease(title: " ")).not_to be_valid
  end

  it "keeps codes unique per tenant, not globally" do
    with_tenant(tenant) { create(:lease, tenant: tenant, code: "LOC-1") }

    expect(with_tenant(tenant) { build_lease(code: "loc-1").valid? }).to be(false)
    expect(with_tenant(other_tenant) { build(:lease, tenant: other_tenant, code: "LOC-1").valid? }).to be(true)
  end

  describe "database constraints" do
    it "rejects an unknown status even without validations" do
      lease = with_tenant(tenant) { create(:lease, tenant: tenant) }

      expect {
        with_tenant(tenant) { Lease.where(id: lease.id).update_all(status: "cancelled") }
      }.to raise_error(ActiveRecord::StatementInvalid, /leases_status_check/)
    end

    it "rejects a property of another tenant (composite foreign key)" do
      foreign_property = with_tenant(other_tenant) { create(:property, tenant: other_tenant) }

      expect {
        with_tenant(tenant) { build_lease(property_id: foreign_property.id).save!(validate: false) }
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_leases_property_same_tenant/)
    end

    it "rejects a duplicate code in the same tenant" do
      with_tenant(tenant) { create(:lease, tenant: tenant, code: "LOC-1") }

      expect {
        with_tenant(tenant) { build_lease(code: "LOC-1").save!(validate: false) }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
