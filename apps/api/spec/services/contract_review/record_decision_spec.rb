require "rails_helper"

# docs/adr/0019-review-decisions.md
RSpec.describe ContractReview::RecordDecision do
  let(:tenant) { create(:tenant) }
  let(:reviewer) { create(:user) }
  let!(:version) do
    with_tenant(tenant) { create(:document_version, contract_document: create(:contract_document, tenant: tenant)) }
  end

  let!(:text) { with_tenant(tenant) { create(:document_text_extraction, document_version: version) } }

  # Every run reads the same text extraction (one pending extraction per version).
  def succeeded_run
    with_tenant(tenant) do
      run = create(:extraction_run, text_extraction: text, status: "running")
      run.update!(status: :succeeded, model_version: "m", field_count: 0, rejected_field_count: 0, finished_at: Time.current)
      run
    end
  end

  let!(:run) { succeeded_run }

  def field(**attributes)
    with_tenant(tenant) { create(:extracted_field, extraction_run: run, **attributes) }
  end

  def decide(target, decision, value: nil, reason: nil)
    with_tenant(tenant) do
      described_class.call(field: target, decision: decision, value: value, reason: reason, reviewed_by: reviewer)
    end
  end

  it "approves a field as is, recording the reviewer, with no value" do
    result = decide(field, "approved")

    expect(result.value).to have_attributes(decision: "approved", value_type: "integer", value_integer: nil,
      reviewed_by_id: reviewer.id)
  end

  it "rejects a field with a stripped reason" do
    expect(decide(field, "rejected", reason: "  Valor é do aditivo, não do contrato.  ").value)
      .to have_attributes(decision: "rejected", reason: "Valor é do aditivo, não do contrato.")
  end

  it "corrects money as an exact decimal, never a float" do
    rent = field(field_key: "monthly_rent", value_type: "money", value_integer: nil, value_amount: BigDecimal("10000"),
      value_currency: "BRL")

    result = decide(rent, "corrected", value: { "amount" => "18500.50", "currency" => "BRL" })

    expect(result.value).to have_attributes(decision: "corrected", value_amount: BigDecimal("18500.50"), value_currency: "BRL")
    expect(decide(rent, "corrected", value: { "amount" => 18500.5, "currency" => "BRL" }).error)
      .to eq("value" => [ "is invalid for monthly_rent" ])
  end

  it "corrects dates, integers, options and parties with the catalog's rules" do
    date = field(field_key: "expiration_date", value_type: "date", value_integer: nil, value_date: Date.new(2029, 3, 31))
    option = field(field_key: "guarantee_type", value_type: "option", value_integer: nil, value_text: "none")
    party = field(field_key: "lessor", value_type: "party", value_integer: nil, value_text: "Alfa")

    expect(decide(date, "corrected", value: { "date" => "2029-03-30" }).value.value_date).to eq(Date.new(2029, 3, 30))
    expect(decide(field, "corrected", value: { "integer" => 48 }).value.value_integer).to eq(48)
    expect(decide(option, "corrected", value: { "option" => "personal_guarantee" }).value.value_text).to eq("personal_guarantee")
    expect(decide(party, "corrected", value: { "name" => "Alfa Ltda", "tax_id" => "12.345.678/0001-90" }).value)
      .to have_attributes(value_text: "Alfa Ltda", value_tax_id: "12345678000190")

    expect(decide(date, "corrected", value: { "date" => "31/03/2029" }).error).to include("value")
    expect(decide(field, "corrected", value: { "integer" => 5000 }).error).to include("value")
    expect(decide(option, "corrected", value: { "option" => "fianca" }).error).to include("value")
    expect(decide(field, "corrected", value: nil).error).to include("value")
  end

  it "refuses a value with an approval or rejection, and an unknown decision" do
    expect(decide(field, "approved", value: { "integer" => 1 }).error).to include("value")
    expect(decide(field, "maybe").error).to eq("decision" => [ "is not included in the list" ])
  end

  it "refuses an overlong reason" do
    expect(decide(field, "rejected", reason: "x" * 1_001).error).to eq("reason" => [ "is too long" ])
  end

  it "keeps every decision: the latest is the field's current state" do
    target = field
    decide(target, "approved")
    decide(target, "rejected", reason: "Revisado de novo")

    expect(with_tenant(tenant) { target.review_decisions.map(&:decision) }).to eq(%w[approved rejected])
  end

  it "refuses fields of an older run once the version has a newer succeeded run (stale_run)" do
    old_field = field
    succeeded_run

    expect(decide(old_field, "approved").error).to eq("stale_run")
    expect(with_tenant(tenant) { ReviewDecision.count }).to eq(0)
  end
end
