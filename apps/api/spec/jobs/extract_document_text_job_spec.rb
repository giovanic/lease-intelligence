require "rails_helper"

# docs/adr/0016-document-text-extraction.md, docs/architecture/background-processing.md
RSpec.describe ExtractDocumentTextJob do
  include ActiveJob::TestHelper

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }
  let!(:lease) { with_tenant(tenant) { create(:lease, tenant: tenant) } }
  let(:ocr) { DocumentTextHelpers::FakeOcr.new({ 2 => "Assinaturas das partes" }) }

  before { allow(Ocr).to receive(:provider).and_return(ocr) }

  def upload(bytes)
    with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "amendment", title: "Aditivo" },
        file: uploaded_file(bytes)).value.versions.first
    end
  end

  def extraction_of(version)
    with_tenant(tenant) { version.latest_text_extraction.reload }
  end

  it "is enqueued by the upload, on the documents queue, with ids only" do
    version = nil
    expect { version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ])) }
      .to have_enqueued_job(described_class).on_queue("documents")

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]).to eq([ tenant.id, extraction_of(version).id ])
  end

  it "is not enqueued when the upload's transaction rolls back" do
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(described_class)
  end

  it "extracts native text and OCRs the scanned page of an uploaded PDF" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL", nil ]))
    described_class.perform_now(tenant.id, extraction_of(version).id)

    extraction = extraction_of(version)
    expect(extraction).to have_attributes(status: "succeeded", page_count: 2, native_page_count: 1, ocr_page_count: 1)
    expect(with_tenant(tenant) { extraction.pages.map(&:text) })
      .to eq([ "CONTRATO DE LOCACAO COMERCIAL", "Assinaturas das partes" ])
  end

  it "is idempotent: running it again stores nothing twice and does not call OCR again" do
    version = upload(build_pdf([ nil ]))
    extraction_id = extraction_of(version).id

    2.times { described_class.perform_now(tenant.id, extraction_id) }

    expect(ocr.requests.size).to eq(1)
    expect(with_tenant(tenant) { DocumentTextPage.where(text_extraction_id: extraction_id).count }).to eq(1)
  end

  it "records an expected failure without raising or retrying" do
    allow(Ocr).to receive(:provider).and_return(DocumentTextHelpers::FakeOcr.new(error: Ocr::TimeoutError.new("x")))
    version = upload(build_pdf([ nil ]))

    expect { described_class.perform_now(tenant.id, extraction_of(version).id) }
      .not_to have_enqueued_job(described_class)
    expect(extraction_of(version)).to have_attributes(status: "failed", error_code: "timeout")
  end

  it "retries unexpected errors and records internal_error when the attempts run out" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
    allow(DocumentText::ExtractPages).to receive(:call).and_raise(RuntimeError, "boom")

    # The block form also performs the retries the job enqueues for itself.
    perform_enqueued_jobs(only: described_class) { described_class.perform_later(tenant.id, extraction_of(version).id) }

    expect(DocumentText::ExtractPages).to have_received(:call).exactly(described_class::ATTEMPTS).times
    expect(extraction_of(version)).to have_attributes(status: "failed", error_code: "internal_error")
  end

  it "fails loudly without a tenant, with an unknown tenant and with a suspended one" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
    extraction_id = extraction_of(version).id
    job = ->(tenant_id) { described_class.new(tenant_id, extraction_id).perform(tenant_id, extraction_id) }

    expect { job.call(nil) }.to raise_error(ApplicationJob::TenantContextError)
    expect { job.call(SecureRandom.uuid) }.to raise_error(ApplicationJob::TenantContextError)
    tenant.update!(status: "suspended")
    expect { job.call(tenant.id) }.to raise_error(ApplicationJob::TenantContextError)
    tenant.update!(status: "active")
    expect(extraction_of(version)).to be_pending
  end

  it "re-raises when the outcome cannot be recorded once the retries run out" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
    job = described_class.new(tenant.id, extraction_of(version).id)

    expect { job.record_internal_error(ApplicationJob::TenantContextError.new("gone")) }
      .to raise_error(ApplicationJob::TenantContextError)
  end

  it "cannot reach another tenant's extraction: RLS hides it" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
    extraction_id = extraction_of(version).id

    expect { described_class.new.perform(other_tenant.id, extraction_id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(extraction_of(version)).to be_pending
  end

  it "leaves no tenant context behind on the connection" do
    version = upload(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))
    described_class.perform_now(tenant.id, extraction_of(version).id)

    expect(ActiveRecord::Base.connection.select_value("SELECT current_setting('app.current_tenant_id', true)")).to be_blank
  end
end
