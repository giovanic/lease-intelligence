require "rails_helper"

RSpec.describe DocumentVersion, type: :model do
  let(:tenant) { create(:tenant) }
  let!(:document) { with_tenant(tenant) { create(:contract_document, tenant: tenant) } }
  let(:connection) { ActiveRecord::Base.connection }

  def build_version(**attributes)
    build(:document_version, contract_document: document, **attributes)
  end

  it "accepts only the supported content types" do
    expect(build_version(content_type: "application/pdf")).to be_valid
    expect(build_version(content_type: "text/html")).not_to be_valid
  end

  it "bounds byte_size between 1 byte and 50 MB" do
    expect(build_version(byte_size: 0)).not_to be_valid
    expect(build_version(byte_size: 50.megabytes)).to be_valid
    expect(build_version(byte_size: 50.megabytes + 1)).not_to be_valid
  end

  it "is read-only once persisted" do
    version = with_tenant(tenant) { create(:document_version, contract_document: document) }

    expect(version).to be_readonly
    expect { with_tenant(tenant) { version.update!(original_filename: "outro.pdf") } }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe "database guarantees" do
    let!(:version) { with_tenant(tenant) { create(:document_version, contract_document: document) } }

    it "rejects any UPDATE, even one bypassing ActiveRecord" do
      expect {
        with_tenant(tenant) do
          connection.execute("UPDATE document_versions SET original_filename = 'x.pdf' WHERE id = #{connection.quote(version.id)}")
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /document_versions rows are immutable \(UPDATE rejected\)/)
    end

    it "rejects any DELETE, even one bypassing ActiveRecord" do
      expect {
        with_tenant(tenant) { connection.execute("DELETE FROM document_versions WHERE id = #{connection.quote(version.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /document_versions rows are immutable \(DELETE rejected\)/)
    end

    it "rejects the same bytes twice in one tenant" do
      duplicate = build_version(sha256: version.sha256, version_number: 99)

      expect { with_tenant(tenant) { duplicate.save!(validate: false) } }
        .to raise_error(ActiveRecord::RecordNotUnique, /idx_document_versions_unique_sha256_per_tenant/)
    end

    it "accepts the same bytes in another tenant" do
      other_tenant = create(:tenant)

      with_tenant(other_tenant) do
        other_document = create(:contract_document, tenant: other_tenant)
        expect(create(:document_version, contract_document: other_document, sha256: version.sha256)).to be_persisted
      end
    end

    it "rejects a malformed checksum and a disallowed content type" do
      expect { with_tenant(tenant) { build_version(sha256: "ABC").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_versions_sha256_format/)
      expect { with_tenant(tenant) { build_version(content_type: "text/html").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_versions_content_type_check/)
    end

    it "rejects a version whose document belongs to another tenant" do
      other_tenant = create(:tenant)
      other_document = with_tenant(other_tenant) { create(:contract_document, tenant: other_tenant) }

      expect {
        with_tenant(tenant) do
          build(:document_version, contract_document: other_document, tenant: tenant).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_document_versions_document_same_tenant/)
    end
  end
end
