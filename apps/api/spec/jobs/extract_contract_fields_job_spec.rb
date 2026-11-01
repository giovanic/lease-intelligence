require "rails_helper"

# docs/adr/0017-contract-field-extraction-claude.md, docs/architecture/background-processing.md
RSpec.describe ExtractContractFieldsJob do
  include ActiveJob::TestHelper

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }
  let!(:lease) { with_tenant(tenant) { create(:lease, tenant: tenant) } }
  let(:answer) do
    output_with("term_months" => [ candidate(60, page: 1, quote: "PRAZO DE 60 MESES") ])
  end
  let(:llm) { FieldExtractionHelpers::FakeLlm.new(answer) }
  let(:ocr) { DocumentTextHelpers::FakeOcr.new }

  before do
    allow(Llm).to receive(:provider).and_return(llm)
    allow(Ocr).to receive(:provider).and_return(ocr)
  end

  # Upload a PDF and run its text extraction: the text job then requests
  # the field extraction (step 4).
  def upload_and_extract_text(text = "CONTRATO DE LOCACAO - PRAZO DE 60 MESES")
    version = with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "original_contract",
        title: "Contrato" }, file: uploaded_file(build_pdf([ text ]))).value.versions.first
    end
    extraction_id = with_tenant(tenant) { version.latest_text_extraction.id }
    ExtractDocumentTextJob.perform_now(tenant.id, extraction_id)
    version
  end

  def run_of(version)
    with_tenant(tenant) { version.reload.latest_extraction_run }
  end

  it "is requested by the text extraction job once the text succeeds, on the documents queue, with ids only" do
    version = nil
    expect { version = upload_and_extract_text }.to have_enqueued_job(described_class).on_queue("documents")

    run = run_of(version)
    expect(run).to have_attributes(status: "pending", requested_by_id: nil,
      text_extraction_id: with_tenant(tenant) { version.latest_text_extraction.id })
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]).to eq([ tenant.id, run.id ])
  end

  it "is not requested when no LLM provider is configured — the text is still stored" do
    allow(Llm).to receive(:provider).and_return(nil)

    version = nil
    expect { version = upload_and_extract_text }.not_to have_enqueued_job(described_class)
    expect(run_of(version)).to be_nil
    expect(with_tenant(tenant) { version.latest_text_extraction }).to be_succeeded
  end

  it "is not requested when the text extraction fails" do
    allow(Ocr).to receive(:provider).and_return(DocumentTextHelpers::FakeOcr.new(error: Ocr::TimeoutError.new("x")))
    version = with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "amendment", title: "A" },
        file: uploaded_file(build_pdf([ nil ]))).value.versions.first
    end

    expect { ExtractDocumentTextJob.perform_now(tenant.id, with_tenant(tenant) { version.latest_text_extraction.id }) }
      .not_to have_enqueued_job(described_class)
  end

  it "stores the validated candidates with their evidence" do
    version = upload_and_extract_text
    described_class.perform_now(tenant.id, run_of(version).id)

    run = run_of(version)
    expect(run).to have_attributes(status: "succeeded", field_count: 1, rejected_field_count: 0,
      model_version: "fake-model-2026", input_tokens: 1200)
    with_tenant(tenant) do
      field = run.fields.sole
      expect(field).to have_attributes(field_key: "term_months", value_integer: 60)
      expect(field.evidence_references.sole.snippet).to eq("PRAZO DE 60 MESES")
    end
  end

  it "is idempotent: running it again stores nothing twice and does not call the provider again" do
    version = upload_and_extract_text
    run_id = run_of(version).id

    2.times { described_class.perform_now(tenant.id, run_id) }

    expect(llm.requests.size).to eq(1)
    expect(with_tenant(tenant) { ExtractedField.where(extraction_run_id: run_id).count }).to eq(1)
  end

  it "records an expected provider failure without raising or retrying" do
    allow(Llm).to receive(:provider).and_return(FieldExtractionHelpers::FakeLlm.new(error: Llm::RefusedError.new("x")))
    version = upload_and_extract_text

    expect { described_class.perform_now(tenant.id, run_of(version).id) }.not_to have_enqueued_job(described_class)
    expect(run_of(version)).to have_attributes(status: "failed", error_code: "refused")
  end

  it "retries unexpected errors and records internal_error when the attempts run out" do
    version = upload_and_extract_text
    allow(FieldExtraction::ExtractFields).to receive(:call).and_raise(RuntimeError, "boom")

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(tenant.id, run_of(version).id) }

    expect(FieldExtraction::ExtractFields).to have_received(:call).exactly(described_class::ATTEMPTS).times
    expect(run_of(version)).to have_attributes(status: "failed", error_code: "internal_error")
  end

  it "records internal_error when the provider is no longer configured" do
    version = upload_and_extract_text
    allow(Llm).to receive(:provider).and_return(nil)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(tenant.id, run_of(version).id) }

    expect(run_of(version)).to have_attributes(status: "failed", error_code: "internal_error")
  end

  it "fails loudly without a tenant, with an unknown tenant and with a suspended one" do
    version = upload_and_extract_text
    run_id = run_of(version).id
    job = ->(tenant_id) { described_class.new(tenant_id, run_id).perform(tenant_id, run_id) }

    expect { job.call(nil) }.to raise_error(ApplicationJob::TenantContextError)
    expect { job.call(SecureRandom.uuid) }.to raise_error(ApplicationJob::TenantContextError)
    tenant.update!(status: "suspended")
    expect { job.call(tenant.id) }.to raise_error(ApplicationJob::TenantContextError)
    tenant.update!(status: "active")
    expect(run_of(version)).to be_pending
    expect(llm.requests).to be_empty
  end

  it "re-raises when the outcome cannot be recorded once the retries run out" do
    version = upload_and_extract_text
    job = described_class.new(tenant.id, run_of(version).id)

    expect { job.record_internal_error(ApplicationJob::TenantContextError.new("gone")) }
      .to raise_error(ApplicationJob::TenantContextError)
  end

  it "cannot reach another tenant's run: RLS hides it" do
    version = upload_and_extract_text
    run_id = run_of(version).id

    expect { described_class.new.perform(other_tenant.id, run_id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(run_of(version)).to be_pending
    expect(llm.requests).to be_empty
  end

  it "leaves no tenant context behind on the connection" do
    version = upload_and_extract_text
    described_class.perform_now(tenant.id, run_of(version).id)

    expect(ActiveRecord::Base.connection.select_value("SELECT current_setting('app.current_tenant_id', true)")).to be_blank
  end
end
