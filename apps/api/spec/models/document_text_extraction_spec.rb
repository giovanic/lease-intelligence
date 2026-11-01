require "rails_helper"

# docs/adr/0016-document-text-extraction.md
RSpec.describe DocumentTextExtraction, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let!(:version) do
    with_tenant(tenant) { create(:document_version, contract_document: create(:contract_document, tenant: tenant)) }
  end
  let!(:other_version) do
    with_tenant(other_tenant) do
      create(:document_version, contract_document: create(:contract_document, tenant: other_tenant))
    end
  end
  let(:connection) { ActiveRecord::Base.connection }

  def build_extraction(**attributes)
    build(:document_text_extraction, document_version: version, **attributes)
  end

  it "requires an error code exactly when failed, from the fixed vocabulary" do
    expect(build_extraction(status: "failed", error_code: "timeout")).to be_valid
    expect(build_extraction(status: "failed")).not_to be_valid
    expect(build_extraction(status: "failed", error_code: "boom: /etc/passwd")).not_to be_valid
    expect(build_extraction(status: "pending", error_code: "timeout")).not_to be_valid
  end

  it "rejects an unknown status" do
    expect(build_extraction(status: "done")).not_to be_valid
  end

  it "is abandoned only when pending/running and untouched for ABANDONED_AFTER" do
    now = Time.current
    stale = now - described_class::ABANDONED_AFTER - 1.second

    expect(build_extraction(status: "running", updated_at: stale).abandoned?(now)).to be(true)
    expect(build_extraction(status: "pending", updated_at: now - 1.minute).abandoned?(now)).to be(false)
    expect(build_extraction(status: "failed", error_code: "timeout", updated_at: stale).abandoned?(now)).to be(false)
  end

  describe "database guarantees" do
    it "allows only one pending/running attempt per version, any number of finished ones" do
      with_tenant(tenant) do
        create(:document_text_extraction, document_version: version, status: "failed", error_code: "timeout")
        create(:document_text_extraction, document_version: version, status: "running")
      end

      expect { with_tenant(tenant) { build_extraction(status: "pending").save!(validate: false) } }
        .to raise_error(ActiveRecord::RecordNotUnique, /idx_document_text_extractions_one_active_per_version/)
    end

    it "rejects an error code outside the vocabulary and a failure without one" do
      expect { with_tenant(tenant) { build_extraction(status: "failed", error_code: "boom").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_text_extractions_error_code_check/)
      expect { with_tenant(tenant) { build_extraction(status: "failed").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_text_extractions_error_code_iff_failed/)
    end

    it "rejects a success whose page counts do not add up" do
      attributes = { status: "succeeded", page_count: 3, native_page_count: 1, ocr_page_count: 1, finished_at: Time.current }

      expect { with_tenant(tenant) { build_extraction(**attributes).save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_text_extractions_succeeded_counts/)
    end

    it "rejects a success with a missing count (NULL must not pass the check)" do
      attributes = { status: "succeeded", page_count: 1, native_page_count: 1, ocr_page_count: nil, finished_at: Time.current }

      expect { with_tenant(tenant) { build_extraction(**attributes).save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /document_text_extractions_succeeded_counts/)
    end

    it "rejects an extraction of another tenant's version" do
      expect {
        with_tenant(tenant) do
          build(:document_text_extraction, document_version: other_version, tenant: tenant).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_document_text_extractions_version_same_tenant/)
    end
  end
end

RSpec.describe DocumentTextPage, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:connection) { ActiveRecord::Base.connection }

  def create_extraction(tenant)
    with_tenant(tenant) do
      version = create(:document_version, contract_document: create(:contract_document, tenant: tenant))
      create(:document_text_extraction, document_version: version)
    end
  end

  let!(:extraction) { create_extraction(tenant) }
  let!(:page) { with_tenant(tenant) { create(:document_text_page, text_extraction: extraction, page_number: 1) } }

  it "accepts only native or ocr as source" do
    expect(build(:document_text_page, text_extraction: extraction, source: "ocr")).to be_valid
    expect(build(:document_text_page, text_extraction: extraction, source: "llm")).not_to be_valid
  end

  it "keeps an empty text (a blank page) but not a missing one" do
    expect(build(:document_text_page, text_extraction: extraction, text: "")).to be_valid
    expect(build(:document_text_page, text_extraction: extraction, text: nil)).not_to be_valid
  end

  it "is read-only once persisted" do
    expect(page).to be_readonly
    expect { with_tenant(tenant) { page.update!(text: "outro") } }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe "database guarantees" do
    it "rejects any UPDATE and DELETE, even bypassing ActiveRecord" do
      expect {
        with_tenant(tenant) { connection.execute("UPDATE document_text_pages SET text = 'x' WHERE id = #{connection.quote(page.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /document_text_pages rows are immutable \(UPDATE rejected\)/)
      expect {
        with_tenant(tenant) { connection.execute("DELETE FROM document_text_pages WHERE id = #{connection.quote(page.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /document_text_pages rows are immutable \(DELETE rejected\)/)
    end

    it "rejects the same page number twice in one extraction" do
      expect { with_tenant(tenant) { build(:document_text_page, text_extraction: extraction, page_number: 1).save! } }
        .to raise_error(ActiveRecord::RecordNotUnique, /idx_document_text_pages_unique_number_per_extraction/)
    end

    it "rejects a page of another tenant's extraction" do
      other_extraction = create_extraction(other_tenant)

      expect {
        with_tenant(tenant) do
          build(:document_text_page, text_extraction: other_extraction, tenant: tenant).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_document_text_pages_extraction_same_tenant/)
    end
  end
end
