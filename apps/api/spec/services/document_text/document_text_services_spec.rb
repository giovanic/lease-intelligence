require "rails_helper"

# Text extraction services (docs/adr/0016-document-text-extraction.md).
RSpec.describe "DocumentText services" do
  let(:tenant) { create(:tenant) }
  let(:user) { create(:user) }
  let!(:document) { with_tenant(tenant) { create(:contract_document, tenant: tenant) } }
  let!(:version) { with_tenant(tenant) { create(:document_version, contract_document: document) } }

  describe DocumentText::RequestExtraction do
    def request(requested_by: nil)
      with_tenant(tenant) { described_class.call(version: version, requested_by: requested_by) }
    end

    it "creates a pending attempt and enqueues the job with ids only" do
      result = nil
      expect { result = request(requested_by: user) }.to have_enqueued_job(ExtractDocumentTextJob)
        .with(tenant.id, kind_of(String)).on_queue("documents")

      extraction = result.value
      expect(extraction).to have_attributes(status: "pending", document_version_id: version.id,
        tenant_id: tenant.id, requested_by_id: user.id)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]).to eq([ tenant.id, extraction.id ])
    end

    it "refuses a second attempt while one is pending or running, without enqueuing" do
      first = request.value
      expect { expect(request.error).to eq("in_progress") }.not_to have_enqueued_job(ExtractDocumentTextJob)

      with_tenant(tenant) { first.update!(status: :running) }
      expect(request.error).to eq("in_progress")
    end

    it "allows a new attempt once the previous one finished" do
      first = request.value
      with_tenant(tenant) { first.update!(status: :failed, error_code: "timeout", finished_at: Time.current) }

      expect(request).to be_success
      expect(with_tenant(tenant) { version.text_extractions.count }).to eq(2)
    end

    it "closes an attempt stuck past ABANDONED_AFTER as abandoned and starts a new one" do
      first = request.value
      with_tenant(tenant) { first.update_columns(status: "running", updated_at: 2.hours.ago) }

      second = request.value
      expect(second).to be_pending
      expect(with_tenant(tenant) { first.reload }).to have_attributes(status: "failed", error_code: "abandoned")
    end

    it "turns a lost race on the one-active index into in_progress" do
      request
      allow(DocumentTextExtraction).to receive(:active).and_return(DocumentTextExtraction.none)

      expect(request.error).to eq("in_progress")
    end
  end

  describe DocumentText::ExtractPages do
    def stored(bytes)
      key = "tenants/#{tenant.id}/document_versions/#{SecureRandom.uuid}"
      Documents::FileStore.upload(key, StringIO.new(bytes), md5_base64: Digest::MD5.base64digest(bytes),
        content_type: "application/octet-stream")
      key
    end

    def extract(bytes, content_type: "application/pdf", ocr: DocumentTextHelpers::FakeOcr.new)
      described_class.call(storage_key: stored(bytes), content_type: content_type, ocr: ocr)
    end

    it "keeps native text and never calls OCR for a digital PDF" do
      ocr = DocumentTextHelpers::FakeOcr.new
      result = extract(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL", "CLAUSULA PRIMEIRA DO OBJETO" ]), ocr: ocr)

      expect(result.value.pages.map(&:to_h)).to eq([
        { number: 1, source: "native", text: "CONTRATO DE LOCACAO COMERCIAL" },
        { number: 2, source: "native", text: "CLAUSULA PRIMEIRA DO OBJETO" }
      ])
      expect(result.value.native_engine).to start_with("pdf-reader ")
      expect(result.value.ocr_engine).to be_nil
      expect(ocr.requests).to be_empty
    end

    it "sends only the pages without enough native text to OCR" do
      ocr = DocumentTextHelpers::FakeOcr.new({ 2 => "Pagina escaneada", 3 => "Assinaturas" })
      result = extract(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL", nil, "Ok." ]), ocr: ocr)

      expect(ocr.requests.sole).to include(content_type: "application/pdf", page_numbers: [ 2, 3 ])
      expect(result.value.pages.map { |page| [ page.number, page.source, page.text ] }).to eq([
        [ 1, "native", "CONTRATO DE LOCACAO COMERCIAL" ], [ 2, "ocr", "Pagina escaneada" ], [ 3, "ocr", "Assinaturas" ]
      ])
      expect(result.value.ocr_engine).to eq("fake-ocr 1.0")
    end

    it "OCRs every frame of an image and normalizes the text it stores" do
      ocr = DocumentTextHelpers::FakeOcr.new({ 1 => "  Locador:\u0000 Fulano  \r\nLocatario   \r\n", 2 => "é" },
        image_pages: 2)
      result = extract(DocumentUploadHelpers::TIFF_HEADER + "frames".b, content_type: "image/tiff", ocr: ocr)

      expect(ocr.requests.sole).to include(content_type: "image/tiff", page_numbers: nil)
      expect(result.value.pages.map(&:text)).to eq([ "Locador: Fulano\nLocatario", "é" ])
      expect(result.value.pages.map(&:source)).to eq(%w[ocr ocr])
      expect(result.value.native_engine).to be_nil
    end

    it "fails with a fixed code for unreadable, encrypted and oversized PDFs" do
      expect(extract("%PDF-1.4 not really a pdf".b).error).to eq("unreadable_file")

      allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::EncryptedPDFError, "needs a password")
      expect(extract(build_pdf([ "x" ])).error).to eq("encrypted_pdf")
    end

    it "refuses more than MAX_PAGES pages" do
      stub_const("DocumentTextExtraction::MAX_PAGES", 2)

      expect(extract(build_pdf([ "a", "b", "c" ])).error).to eq("too_many_pages")
      ocr = DocumentTextHelpers::FakeOcr.new(image_pages: 3)
      expect(extract(DocumentUploadHelpers::PNG_HEADER + "x".b, content_type: "image/png", ocr: ocr).error)
        .to eq("too_many_pages")
    end

    it "maps OCR errors to error codes" do
      {
        Ocr::TimeoutError => "timeout", Ocr::UnreadableFileError => "unreadable_file",
        Ocr::UnavailableError => "ocr_unavailable"
      }.each do |error, code|
        ocr = DocumentTextHelpers::FakeOcr.new(error: error.new("fixed message"))
        expect(extract(build_pdf([ nil ]), ocr: ocr).error).to eq(code)
      end
    end

    it "fails with storage_unavailable when the bytes cannot be read" do
      result = described_class.call(storage_key: "tenants/#{tenant.id}/document_versions/missing",
        content_type: "application/pdf", ocr: DocumentTextHelpers::FakeOcr.new)

      expect(result.error).to eq("storage_unavailable")
    end

    it "raises when the provider answers for other pages than asked" do
      ocr = DocumentTextHelpers::FakeOcr.new
      allow(ocr).to receive(:recognize).and_return([ Ocr::Page.new(number: 9, text: "x") ])

      expect { extract(build_pdf([ nil ]), ocr: ocr) }.to raise_error(ArgumentError, /returned 1 pages for 1 requested/)
    end

    it "leaves no temp file behind" do
      created = []
      allow(Dir).to receive(:mktmpdir).and_wrap_original { |original, *args, &block| original.call(*args) { |dir| created << dir; block.call(dir) } }
      extract(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]))

      expect(created.size).to eq(1)
      expect(File.exist?(created.first)).to be(false)
    end
  end

  describe "StartExtraction and RecordOutcome" do
    let!(:extraction) { with_tenant(tenant) { create(:document_text_extraction, document_version: version) } }
    let(:extracted) do
      DocumentText::ExtractPages::Extracted.new(
        pages: [
          DocumentText::ExtractPages::PageText.new(1, "native", "Clausula 1"),
          DocumentText::ExtractPages::PageText.new(2, "ocr", "Clausula 2")
        ],
        native_engine: "pdf-reader 2.16.0", ocr_engine: "fake-ocr 1.0"
      )
    end

    def start
      with_tenant(tenant) { DocumentText::StartExtraction.call(extraction.id) }
    end

    def record(result)
      with_tenant(tenant) { DocumentText::RecordOutcome.call(extraction_id: extraction.id, result: result) }
    end

    it "marks the attempt running and returns where the file is" do
      source = start.value

      expect(source.to_h).to eq(storage_key: version.storage_key, content_type: "application/pdf")
      expect(with_tenant(tenant) { extraction.reload }).to have_attributes(status: "running", started_at: be_present)
    end

    it "resumes a running attempt keeping its first start time" do
      start
      first_start = with_tenant(tenant) { extraction.reload.started_at }

      travel 1.minute do
        expect(start).to be_success
        expect(with_tenant(tenant) { extraction.reload.started_at }).to eq(first_start)
      end
    end

    it "stores every page and the counts in one go" do
      start
      record(ServiceResult.success(extracted))

      with_tenant(tenant) do
        expect(extraction.reload).to have_attributes(status: "succeeded", page_count: 2, native_page_count: 1,
          ocr_page_count: 1, native_engine: "pdf-reader 2.16.0", ocr_engine: "fake-ocr 1.0", error_code: nil,
          finished_at: be_present)
        expect(extraction.pages.map { |page| [ page.page_number, page.source, page.text, page.tenant_id ] })
          .to eq([ [ 1, "native", "Clausula 1", tenant.id ], [ 2, "ocr", "Clausula 2", tenant.id ] ])
      end
    end

    it "keeps the page text out of the SQL log, even at debug level" do
      log = StringIO.new
      logger = ActiveSupport::Logger.new(log).tap { |l| l.level = :debug }
      original = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = logger
      begin
        record(ServiceResult.success(extracted))
      ensure
        ActiveRecord::Base.logger = original
      end

      expect(log.string).to include("INSERT INTO \"document_text_pages\"")
      expect(log.string).not_to include("Clausula")
      expect(with_tenant(tenant) { extraction.pages.first.inspect }).to include("text: [FILTERED]")
    end

    it "records a failure with its code and no pages" do
      record(ServiceResult.failure("timeout"))

      with_tenant(tenant) do
        expect(extraction.reload).to have_attributes(status: "failed", error_code: "timeout", finished_at: be_present)
        expect(extraction.pages).to be_empty
      end
    end

    it "never touches a finished attempt again" do
      record(ServiceResult.success(extracted))

      expect(start.error).to eq("finished")
      expect(record(ServiceResult.success(extracted)).error).to eq("finished")
      expect(record(ServiceResult.failure("timeout")).error).to eq("finished")
      with_tenant(tenant) do
        expect(extraction.reload).to be_succeeded
        expect(extraction.pages.count).to eq(2)
      end
    end
  end
end
