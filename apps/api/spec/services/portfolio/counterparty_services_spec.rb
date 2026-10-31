require "rails_helper"

RSpec.describe "Portfolio counterparty services" do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:attributes) { { kind: "individual", legal_name: "Maria Locadora", tax_id: "529.982.247-25" } }

  describe Portfolio::CreateCounterparty do
    it "creates the counterparty in the given tenant even if the attributes name another one" do
      result = with_tenant(tenant) do
        described_class.call(tenant: tenant, attributes: attributes.merge(tenant_id: other_tenant.id))
      end

      expect(result).to be_success
      expect(result.value.tenant_id).to eq(tenant.id)
      expect(result.value.tax_id).to eq("52998224725")
    end

    it "returns the validation errors as a failure" do
      result = with_tenant(tenant) do
        described_class.call(tenant: tenant, attributes: attributes.merge(kind: "company"))
      end

      expect(result).to be_failure
      expect(result.error[:tax_id]).to eq([ "is not a valid CNPJ" ])
    end
  end

  describe Portfolio::UpdateCounterparty do
    it "archives the counterparty" do
      counterparty = with_tenant(tenant) { create(:counterparty, tenant: tenant) }

      result = with_tenant(tenant) { described_class.call(counterparty: counterparty, attributes: { status: "archived" }) }

      expect(result).to be_success
      expect(result.value).to be_archived
    end
  end

  describe Portfolio::CounterpartiesQuery do
    it "orders by legal name and ignores punctuation when searching the tax id" do
      with_tenant(tenant) do
        create(:counterparty, :individual, tenant: tenant, legal_name: "Zeca", tax_id: "52998224725")
        create(:counterparty, tenant: tenant, legal_name: "Ana")

        expect(described_class.call(Counterparty.all).pluck(:legal_name)).to eq(%w[Ana Zeca])
        expect(described_class.call(Counterparty.all, search: "529.982").pluck(:legal_name)).to eq([ "Zeca" ])
      end
    end
  end
end
