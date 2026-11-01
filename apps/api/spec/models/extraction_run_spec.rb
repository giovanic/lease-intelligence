require "rails_helper"

# docs/adr/0017-contract-field-extraction-claude.md
RSpec.describe ExtractionRun, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let!(:text) do
    with_tenant(tenant) do
      create(:document_text_extraction,
        document_version: create(:document_version, contract_document: create(:contract_document, tenant: tenant)))
    end
  end
  let!(:other_text) do
    with_tenant(other_tenant) do
      create(:document_text_extraction,
        document_version: create(:document_version, contract_document: create(:contract_document, tenant: other_tenant)))
    end
  end

  def build_run(**attributes)
    build(:extraction_run, text_extraction: text, **attributes)
  end

  it "requires an error code exactly when failed, from the fixed vocabulary" do
    expect(build_run(status: "failed")).not_to be_valid
    expect(build_run(status: "failed", error_code: "refused")).to be_valid
    expect(build_run(status: "failed", error_code: "boom")).not_to be_valid
    expect(build_run(error_code: "refused")).not_to be_valid
  end

  it "requires provider, model, prompt version and effort" do
    expect(build_run(provider: nil, model: nil, prompt_version: nil, effort: nil).tap(&:valid?).errors.attribute_names)
      .to include(:provider, :model, :prompt_version, :effort)
  end

  it "is abandoned only when pending/running and untouched for ABANDONED_AFTER" do
    now = Time.current
    stale = now - described_class::ABANDONED_AFTER - 1.second

    expect(build_run(status: "running", updated_at: stale).abandoned?(now)).to be(true)
    expect(build_run(status: "pending", updated_at: now).abandoned?(now)).to be(false)
    expect(build_run(status: "failed", error_code: "timeout", updated_at: stale).abandoned?(now)).to be(false)
  end

  describe "database guarantees" do
    it "allows only one pending/running run per version, any number of finished ones" do
      with_tenant(tenant) do
        build_run(status: "failed", error_code: "timeout").save!
        build_run(status: "failed", error_code: "refused").save!
        build_run.save!
      end

      expect { with_tenant(tenant) { build_run(status: "running").save!(validate: false) } }
        .to raise_error(ActiveRecord::RecordNotUnique, /idx_extraction_runs_one_active_per_version/)
    end

    it "rejects an error code outside the vocabulary and a success without counts or model version" do
      expect { with_tenant(tenant) { build_run(status: "failed", error_code: "boom").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /extraction_runs_error_code_check/)
      expect {
        with_tenant(tenant) { build_run(status: "succeeded", field_count: 1, finished_at: Time.current).save!(validate: false) }
      }.to raise_error(ActiveRecord::StatementInvalid, /extraction_runs_succeeded_counts/)
      expect {
        with_tenant(tenant) do
          build_run(status: "succeeded", model_version: "m", rejected_field_count: 0, finished_at: Time.current)
            .save!(validate: false)
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /extraction_runs_succeeded_counts/)
    end

    it "rejects negative token usage" do
      expect { with_tenant(tenant) { build_run(input_tokens: -1).save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /extraction_runs_usage_non_negative/)
    end

    it "rejects a run of another tenant's version" do
      expect {
        with_tenant(tenant) do
          build(:extraction_run, text_extraction: other_text, tenant: tenant).save!(validate: false)
        end
        # Both composite FKs reject it; which one PostgreSQL checks first is not specified.
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_extraction_runs_(version_same_tenant|text_same_version)/)
    end

    it "rejects a run reading the text of a different version than its own" do
      another_text = with_tenant(tenant) do
        create(:document_text_extraction,
          document_version: create(:document_version, contract_document: text.document_version.contract_document,
            version_number: 2))
      end

      expect {
        with_tenant(tenant) do
          build(:extraction_run, text_extraction: another_text, document_version: text.document_version).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_extraction_runs_text_same_version/)
    end
  end
end

# A run (over a text extraction and version) built entirely in `tenant`.
def create_extraction_run(tenant)
  version = create(:document_version, contract_document: create(:contract_document, tenant: tenant))
  create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: version))
end

RSpec.describe ExtractedField, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:connection) { ActiveRecord::Base.connection }
  let!(:run) { with_tenant(tenant) { create_extraction_run(tenant) } }
  let!(:other_run) { with_tenant(other_tenant) { create_extraction_run(other_tenant) } }

  def save_raw(**attributes)
    with_tenant(tenant) do
      build(:extracted_field, extraction_run: run, value_integer: nil, **attributes).save!(validate: false)
    end
  end

  it "accepts only the documented value types" do
    expect(build(:extracted_field, extraction_run: run, value_type: "float")).not_to be_valid
  end

  it "is read-only once persisted" do
    field = with_tenant(tenant) { create(:extracted_field, extraction_run: run) }

    expect(field).to be_readonly
  end

  describe "database guarantees" do
    it "stores each kind of value in its own typed column, money as an exact decimal with a currency" do
      field = with_tenant(tenant) do
        create(:extracted_field, extraction_run: run, field_key: "monthly_rent", value_type: "money", value_integer: nil,
          value_amount: BigDecimal("9999999999999.99"), value_currency: "BRL")
      end

      expect(with_tenant(tenant) { field.reload.value_amount }).to eq(BigDecimal("9999999999999.99"))
    end

    it "rejects a value in the wrong column for its type, or a missing one" do
      check = /extracted_fields_value_matches_type/

      expect { save_raw(value_type: "integer") }.to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(value_type: "integer", value_integer: 5, value_text: "x") }
        .to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(value_type: "money", value_amount: BigDecimal("10")) }
        .to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(value_type: "money", value_amount: BigDecimal("-1"), value_currency: "BRL") }
        .to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(value_type: "party", value_text: "Alfa", value_tax_id: "123") }
        .to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(value_type: "option", value_text: "IGP-M") }.to raise_error(ActiveRecord::StatementInvalid, check)
    end

    it "rejects any UPDATE and DELETE, even bypassing ActiveRecord" do
      field = with_tenant(tenant) { create(:extracted_field, extraction_run: run) }

      expect {
        with_tenant(tenant) { connection.execute("UPDATE extracted_fields SET value_integer = 1 WHERE id = #{connection.quote(field.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      expect {
        with_tenant(tenant) { connection.execute("DELETE FROM extracted_fields WHERE id = #{connection.quote(field.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it "rejects a field of another tenant's run" do
      expect {
        with_tenant(tenant) { build(:extracted_field, extraction_run: other_run, tenant: tenant).save!(validate: false) }
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_extracted_fields_run_same_tenant/)
    end
  end
end

RSpec.describe EvidenceReference, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:connection) { ActiveRecord::Base.connection }
  let!(:field) { with_tenant(tenant) { create(:extracted_field, extraction_run: create_extraction_run(tenant)) } }
  let!(:other_page) do
    with_tenant(other_tenant) do
      create(:document_text_page, text_extraction: create_extraction_run(other_tenant).text_extraction)
    end
  end

  it "slices its snippet from the stored page text" do
    evidence = with_tenant(tenant) { create(:evidence_reference, extracted_field: field, start_offset: 9, end_offset: 17) }

    expect(with_tenant(tenant) { evidence.reload.snippet }).to eq("60 meses")
  end

  it "requires a non-empty span" do
    expect(build(:evidence_reference, start_offset: 5, end_offset: 5)).not_to be_valid
  end

  describe "database guarantees" do
    it "rejects an empty or negative span" do
      expect {
        with_tenant(tenant) { build(:evidence_reference, extracted_field: field, start_offset: 4, end_offset: 4).save!(validate: false) }
      }.to raise_error(ActiveRecord::StatementInvalid, /evidence_references_span_valid/)
    end

    it "rejects any UPDATE and DELETE, even bypassing ActiveRecord" do
      evidence = with_tenant(tenant) { create(:evidence_reference, extracted_field: field) }

      expect {
        with_tenant(tenant) { connection.execute("UPDATE evidence_references SET end_offset = 9 WHERE id = #{connection.quote(evidence.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      expect {
        with_tenant(tenant) { connection.execute("DELETE FROM evidence_references WHERE id = #{connection.quote(evidence.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it "rejects evidence pointing at another tenant's page" do
      expect {
        with_tenant(tenant) do
          build(:evidence_reference, extracted_field: field, text_page: other_page, page_number: 1).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_evidence_references_page_same_tenant/)
    end
  end
end
