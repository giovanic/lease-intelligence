require "rails_helper"

RSpec.describe "Leases services" do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let!(:property) { with_tenant(tenant) { create(:property, tenant: tenant) } }
  let!(:lessor) { with_tenant(tenant) { create(:counterparty, tenant: tenant) } }
  let!(:guarantor) { with_tenant(tenant) { create(:counterparty, :individual, tenant: tenant) } }

  def create_lease(**attributes)
    defaults = { title: "Loja Centro", property_id: property.id, parties: [ { counterparty_id: lessor.id, role: "lessor" } ] }
    with_tenant(tenant) { Leases::CreateLease.call(tenant: tenant, attributes: defaults.merge(attributes)) }
  end

  def update_lease(lease, **attributes)
    with_tenant(tenant) { Leases::UpdateLease.call(lease: Lease.find(lease.id), attributes: attributes) }
  end

  describe Leases::CreateLease do
    it "creates the lease with its parties in the given tenant, as a draft by default" do
      result = create_lease(parties: [
        { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: guarantor.id, role: "guarantor" }
      ])

      expect(result).to be_success
      lease = result.value
      expect(lease).to have_attributes(tenant_id: tenant.id, property_id: property.id, status: "draft")
      expect(lease.lease_parties.map { |party| [ party.counterparty_id, party.role, party.tenant_id ] })
        .to eq([ [ lessor.id, "lessor", tenant.id ], [ guarantor.id, "guarantor", tenant.id ] ])
    end

    it "ignores a tenant_id in the attributes" do
      result = create_lease(tenant_id: other_tenant.id)

      expect(result.value.tenant_id).to eq(tenant.id)
    end

    it "requires a property and at least one lessor" do
      result = create_lease(property_id: nil, parties: [ { counterparty_id: guarantor.id, role: "guarantor" } ])

      expect(result).not_to be_success
      expect(result.error.to_hash).to include(
        property_id: [ "can't be blank" ], parties: [ "must include at least one lessor" ]
      )
      expect(result.error.to_hash).not_to have_key(:property)
      expect(with_tenant(tenant) { Lease.count }).to eq(0)
    end

    it "treats a property or counterparty of another tenant as not found" do
      foreign_property = with_tenant(other_tenant) { create(:property, tenant: other_tenant) }
      foreign_counterparty = with_tenant(other_tenant) { create(:counterparty, tenant: other_tenant) }

      result = create_lease(property_id: foreign_property.id, parties: [
        { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: foreign_counterparty.id, role: "guarantor" }
      ])

      expect(result.error.to_hash).to eq(
        property_id: [ "not found" ], "parties[1].counterparty_id": [ "not found" ]
      )
    end

    it "treats a malformed id as not found" do
      result = create_lease(property_id: "abc", parties: [ { counterparty_id: "abc", role: "lessor" } ])

      expect(result.error.to_hash).to eq(property_id: [ "not found" ], "parties[0].counterparty_id": [ "not found" ])
    end

    it "rejects an archived property or counterparty" do
      with_tenant(tenant) do
        property.update!(status: "archived")
        lessor.update!(status: "archived")
      end

      result = create_lease

      expect(result.error.to_hash).to eq(property_id: [ "is archived" ], "parties[0].counterparty_id": [ "is archived" ])
    end

    it "rejects an unknown role and a repeated counterparty" do
      result = create_lease(parties: [
        { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: lessor.id, role: "guarantor" },
        { counterparty_id: guarantor.id, role: "tenant" }
      ])

      expect(result.error.to_hash).to eq(
        "parties[2].role": [ "is not included in the list" ], parties: [ "must not repeat a counterparty" ]
      )
    end

    it "reports the lease's own validation errors together with the party errors" do
      result = create_lease(title: " ", status: "cancelled", parties: [])

      expect(result.error.to_hash.keys).to contain_exactly(:title, :status, :parties)
    end
  end

  describe Leases::UpdateLease do
    let!(:lease) { create_lease.value }

    it "updates the lease's own attributes and keeps the parties when they are omitted" do
      result = update_lease(lease, title: "Loja Centro (renovado)", status: "active")

      expect(result).to be_success
      expect(result.value.title).to eq("Loja Centro (renovado)")
      expect(with_tenant(tenant) { result.value.lease_parties.map(&:counterparty_id) }).to eq([ lessor.id ])
    end

    it "replaces the parties, keeping a retained party's row and updating its role" do
      original_party_id = lease.lease_parties.first.id

      result = update_lease(lease, parties: [
        { counterparty_id: guarantor.id, role: "lessor" }, { counterparty_id: lessor.id, role: "intervening_party" }
      ])

      expect(result).to be_success
      parties = result.value.lease_parties.index_by(&:counterparty_id)
      expect(parties.transform_values(&:role)).to eq(guarantor.id => "lessor", lessor.id => "intervening_party")
      expect(parties[lessor.id].id).to eq(original_party_id)
    end

    it "removes a party left out of the list" do
      update_lease(lease, parties: [ { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: guarantor.id, role: "guarantor" } ])

      result = update_lease(lease, parties: [ { counterparty_id: guarantor.id, role: "lessor" } ])

      expect(result.value.lease_parties.map(&:counterparty_id)).to eq([ guarantor.id ])
      expect(with_tenant(tenant) { LeaseParty.count }).to eq(1)
    end

    it "rejects an empty party list and changes nothing" do
      result = update_lease(lease, title: "Outro", parties: [])

      expect(result.error.to_hash).to eq(parties: [ "must include at least one lessor" ])
      expect(with_tenant(tenant) { [ lease.reload.title, LeaseParty.count ] }).to eq([ "Loja Centro", 1 ])
    end

    it "keeps a counterparty that was archived after being linked" do
      with_tenant(tenant) { lessor.update!(status: "archived") }

      result = update_lease(lease, parties: [ { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: guarantor.id, role: "guarantor" } ])

      expect(result).to be_success
    end

    it "changes the property while the lease is a draft" do
      other_property = with_tenant(tenant) { create(:property, tenant: tenant) }

      result = update_lease(lease, property_id: other_property.id)

      expect(result.value.property_id).to eq(other_property.id)
    end

    it "does not change the property once the lease left draft" do
      other_property = with_tenant(tenant) { create(:property, tenant: tenant) }
      update_lease(lease, status: "active")

      result = update_lease(lease, property_id: other_property.id, status: "draft")

      expect(result.error.to_hash).to eq(property_id: [ "can only change while the lease is a draft" ])
      expect(with_tenant(tenant) { lease.reload.property_id }).to eq(property.id)
    end

    it "accepts the current property even when it is no longer a draft or the property is archived" do
      update_lease(lease, status: "active")
      with_tenant(tenant) { property.update!(status: "archived") }

      expect(update_lease(lease, property_id: property.id, notes: "ok")).to be_success
    end

    it "rolls the lease back when saving a party fails" do
      allow_any_instance_of(LeaseParty).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        update_lease(lease, title: "Não deve salvar", parties: [ { counterparty_id: guarantor.id, role: "lessor" } ])
      }.to raise_error(ActiveRecord::RecordInvalid)
      expect(with_tenant(tenant) { lease.reload.title }).to eq("Loja Centro")
    end
  end
end
