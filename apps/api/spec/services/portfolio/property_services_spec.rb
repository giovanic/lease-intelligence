require "rails_helper"

RSpec.describe "Portfolio property services" do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:attributes) do
    { name: "Loja 1", property_type: "retail", street: "Rua A", city: "Recife", state: "PE" }
  end

  describe Portfolio::CreateProperty do
    it "creates the property in the given tenant" do
      result = with_tenant(tenant) { described_class.call(tenant: tenant, attributes: attributes) }

      expect(result).to be_success
      expect(result.value).to be_persisted
      expect(result.value.tenant_id).to eq(tenant.id)
    end

    it "uses the given tenant even if the attributes name another one" do
      result = with_tenant(tenant) do
        described_class.call(tenant: tenant, attributes: attributes.merge(tenant_id: other_tenant.id))
      end

      expect(result.value.tenant_id).to eq(tenant.id)
    end

    it "returns the validation errors as a failure" do
      result = with_tenant(tenant) { described_class.call(tenant: tenant, attributes: attributes.merge(name: "")) }

      expect(result).to be_failure
      expect(result.error).to be_a(ActiveModel::Errors)
      expect(result.error[:name]).to be_present
    end
  end

  describe Portfolio::UpdateProperty do
    let(:property) { with_tenant(tenant) { create(:property, tenant: tenant) } }

    it "archives the property" do
      result = with_tenant(tenant) { described_class.call(property: property, attributes: { status: "archived" }) }

      expect(result).to be_success
      expect(result.value).to be_archived
    end

    it "returns a failure and does not persist an invalid change" do
      result = with_tenant(tenant) { described_class.call(property: property, attributes: { state: "XX" }) }

      expect(result).to be_failure
      expect(with_tenant(tenant) { property.reload.state }).to eq("SP")
    end
  end

  describe Portfolio::PropertiesQuery do
    it "escapes LIKE wildcards in the search term" do
      with_tenant(tenant) do
        create(:property, tenant: tenant, name: "100% Fitness")
        create(:property, tenant: tenant, name: "Academia")

        expect(described_class.call(Property.all, search: "100%").pluck(:name)).to eq([ "100% Fitness" ])
        expect(described_class.call(Property.all, search: "%").pluck(:name)).to eq([ "100% Fitness" ])
      end
    end
  end
end
