require "rails_helper"

RSpec.describe ContractDocument, type: :model do
  let(:tenant) { create(:tenant) }
  let!(:lease) { with_tenant(tenant) { create(:lease, tenant: tenant) } }

  def build_document(**attributes)
    build(:contract_document, tenant: tenant, lease: lease, **attributes)
  end

  it "requires a title and strips it" do
    expect(build_document(title: "   ")).not_to be_valid
    expect(build_document(title: "  Contrato original  ").title).to eq("Contrato original")
  end

  it "rejects an unknown kind" do
    document = build_document(kind: "invoice")

    expect(document).not_to be_valid
    expect(document.errors[:kind]).to be_present
  end

  it "allows a single original contract per lease, but many amendments" do
    with_tenant(tenant) do
      create(:contract_document, tenant: tenant, lease: lease, kind: "original_contract")
      create(:contract_document, tenant: tenant, lease: lease, kind: "amendment")

      second_original = build_document(kind: "original_contract")
      expect(second_original).not_to be_valid
      expect(second_original.errors[:kind]).to include("the lease already has an original contract")
      expect(build_document(kind: "amendment")).to be_valid
    end
  end

  it "enforces the single original contract in the database too" do
    with_tenant(tenant) { create(:contract_document, tenant: tenant, lease: lease, kind: "original_contract") }

    expect { with_tenant(tenant) { build_document(kind: "original_contract").save!(validate: false) } }
      .to raise_error(ActiveRecord::RecordNotUnique, /idx_contract_documents_one_original_per_lease/)
  end

  it "rejects, in the database, a document whose lease belongs to another tenant" do
    other_tenant = create(:tenant)
    other_lease = with_tenant(other_tenant) { create(:lease, tenant: other_tenant) }

    expect {
      with_tenant(tenant) { build(:contract_document, tenant: tenant, lease: other_lease).save!(validate: false) }
    }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_contract_documents_lease_same_tenant/)
  end

  it "lists versions newest first" do
    with_tenant(tenant) do
      document = create(:contract_document, tenant: tenant, lease: lease)
      first = create(:document_version, contract_document: document, version_number: 1)
      second = create(:document_version, contract_document: document, version_number: 2)

      expect(document.versions.to_a).to eq([ second, first ])
      expect(document.latest_version).to eq(second)
    end
  end
end
