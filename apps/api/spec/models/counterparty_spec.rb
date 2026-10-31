require "rails_helper"

RSpec.describe Counterparty, type: :model do
  let(:tenant) { create(:tenant) }

  it { is_expected.to belong_to(:tenant) }

  it "is valid as a company with a CNPJ and as an individual with a CPF" do
    with_tenant(tenant) do
      expect(build(:counterparty, tenant: tenant)).to be_valid
      expect(build(:counterparty, :individual, tenant: tenant)).to be_valid
    end
  end

  it "accepts a formatted tax id and stores digits only" do
    counterparty = build(:counterparty, tenant: tenant, tax_id: "11.222.333/0001-81")

    expect(counterparty.tax_id).to eq("11222333000181")
  end

  it "rejects a CPF for a company and a CNPJ for an individual" do
    with_tenant(tenant) do
      company = build(:counterparty, tenant: tenant, kind: "company", tax_id: "52998224725")
      individual = build(:counterparty, tenant: tenant, kind: "individual", tax_id: "11222333000181")

      expect(company).not_to be_valid
      expect(company.errors[:tax_id]).to include("is not a valid CNPJ")
      expect(individual).not_to be_valid
      expect(individual.errors[:tax_id]).to include("is not a valid CPF")
    end
  end

  it "rejects a tax id with a wrong check digit" do
    with_tenant(tenant) { expect(build(:counterparty, tenant: tenant, tax_id: "11222333000180")).not_to be_valid }
  end

  it "allows the tax id to be unknown" do
    with_tenant(tenant) { expect(build(:counterparty, tenant: tenant, tax_id: nil)).to be_valid }
  end

  it "keeps the tax id unique within a tenant only" do
    other_tenant = create(:tenant)
    with_tenant(tenant) { create(:counterparty, tenant: tenant, tax_id: "11222333000181") }

    with_tenant(tenant) { expect(build(:counterparty, tenant: tenant, tax_id: "11222333000181")).not_to be_valid }
    with_tenant(other_tenant) do
      expect(build(:counterparty, tenant: other_tenant, tax_id: "11222333000181")).to be_valid
    end
  end

  it "downcases the email and rejects a malformed one" do
    with_tenant(tenant) do
      expect(build(:counterparty, tenant: tenant, email: "Locador@Example.COM").email).to eq("locador@example.com")
      expect(build(:counterparty, tenant: tenant, email: "not-an-email")).not_to be_valid
    end
  end

  it "rejects an unknown kind as a validation error" do
    with_tenant(tenant) { expect(build(:counterparty, tenant: tenant, kind: "trust", tax_id: nil)).not_to be_valid }
  end

  describe "database constraints (bypassing model validations)" do
    it "rejects a tax id whose length does not match the kind" do
      counterparty = build(:counterparty, tenant: tenant, kind: "individual", tax_id: "11222333000181")

      expect {
        with_tenant(tenant) { counterparty.save!(validate: false) }
      }.to raise_error(ActiveRecord::StatementInvalid, /counterparties_tax_id_format_check/)
    end

    it "rejects a duplicate tax id in the same tenant" do
      with_tenant(tenant) { create(:counterparty, tenant: tenant, tax_id: "11222333000181") }

      expect {
        with_tenant(tenant) { build(:counterparty, tenant: tenant, tax_id: "11222333000181").save!(validate: false) }
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
