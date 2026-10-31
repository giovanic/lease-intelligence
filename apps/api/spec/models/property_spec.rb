require "rails_helper"

RSpec.describe Property, type: :model do
  let(:tenant) { create(:tenant) }

  def build_property(**attributes)
    build(:property, tenant: tenant, **attributes)
  end

  it { is_expected.to belong_to(:tenant) }

  it "is valid with the factory defaults" do
    with_tenant(tenant) { expect(build_property).to be_valid }
  end

  it "requires name, street, city and state" do
    with_tenant(tenant) do
      property = build_property(name: " ", street: nil, city: "", state: nil)

      expect(property).not_to be_valid
      expect(property.errors.attribute_names).to include(:name, :street, :city, :state)
    end
  end

  it "rejects an unknown property_type or status as a validation error, not an exception" do
    with_tenant(tenant) do
      property = build_property(property_type: "castle", status: "deleted")

      expect(property).not_to be_valid
      expect(property.errors.attribute_names).to include(:property_type, :status)
    end
  end

  it "normalizes the postal code to digits, and state, country and code to upper case" do
    property = build_property(postal_code: "01310-100", state: "sp", country_code: "br", code: " sp-014 ")

    expect(property).to have_attributes(postal_code: "01310100", state: "SP", country_code: "BR", code: "SP-014")
  end

  it "requires a real Brazilian state when the country is BR" do
    with_tenant(tenant) do
      expect(build_property(state: "XX")).not_to be_valid
      expect(build_property(state: "XX", country_code: "PT")).to be_valid
    end
  end

  it "rejects a postal code that is not 8 digits" do
    with_tenant(tenant) { expect(build_property(postal_code: "1234")).not_to be_valid }
  end

  describe "area_sqm" do
    it "keeps the decimal value exactly" do
      property = with_tenant(tenant) { create(:property, tenant: tenant, area_sqm: "1234.56") }

      with_tenant(tenant) { expect(property.reload.area_sqm).to eq(BigDecimal("1234.56")) }
    end

    it "must be positive when present" do
      with_tenant(tenant) do
        expect(build_property(area_sqm: 0)).not_to be_valid
        expect(build_property(area_sqm: nil)).to be_valid
      end
    end
  end

  it "keeps the internal code unique within a tenant only" do
    other_tenant = create(:tenant)
    with_tenant(tenant) { create(:property, tenant: tenant, code: "SP-014") }

    with_tenant(tenant) { expect(build_property(code: "sp-014")).not_to be_valid }
    with_tenant(other_tenant) { expect(build(:property, tenant: other_tenant, code: "SP-014")).to be_valid }
  end

  describe "database constraints (bypassing model validations)" do
    # The raise must leave `with_tenant` so its savepoint rolls back
    # (see spec/security/row_level_security_spec.rb).
    it "rejects a non-positive area" do
      expect {
        with_tenant(tenant) { build_property(area_sqm: -1).save!(validate: false) }
      }.to raise_error(ActiveRecord::StatementInvalid, /properties_area_sqm_positive_check/)
    end

    it "rejects a duplicate code in the same tenant" do
      with_tenant(tenant) { create(:property, tenant: tenant, code: "SP-014") }

      expect {
        with_tenant(tenant) { build_property(code: "SP-014").save!(validate: false) }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
