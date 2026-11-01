require "rails_helper"

# Request layer of the three-layer tenant isolation test for AI field
# extraction runs (docs/adr/0017), plus the contract documented in
# Api::V1::ExtractionRunsController and the `extraction_run` field of the
# version JSON.
RSpec.describe "/api/v1/extraction_runs", type: :request do
  let(:user) { create(:user) }
  # Both organizations consented to AI extraction (docs/adr/0018); the default is off.
  let(:tenant_a) { create(:tenant, ai_extraction_enabled: true) }
  let(:tenant_b) { create(:tenant, ai_extraction_enabled: true) }
  let(:role) { "manager" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let(:llm) { FieldExtractionHelpers::FakeLlm.new }
  let!(:lease) { with_tenant(tenant_a) { create(:lease, tenant: tenant_a) } }
  let!(:version) { upload_version(tenant_a, lease) }

  def upload_version(tenant, lease)
    with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "original_contract",
        title: "Contrato" }, file: uploaded_file).value.versions.first
    end
  end

  # Marks the version's text extraction succeeded, with one OCR'd page.
  def succeed_text(version, tenant: tenant_a, text: "Aluguel mensal de R$ 10.000,00 pelo prazo de 60 meses.")
    with_tenant(tenant) do
      extraction = version.reload.latest_text_extraction
      page = create(:document_text_page, text_extraction: extraction, page_number: 1, source: "ocr", text: text)
      extraction.update!(status: :succeeded, page_count: 1, native_page_count: 0, ocr_page_count: 1,
        finished_at: Time.current)
      [ extraction, page ]
    end
  end

  # A succeeded run with a money and a party candidate, each with evidence.
  def succeeded_run(version, tenant: tenant_a)
    extraction, page = succeed_text(version, tenant: tenant)
    with_tenant(tenant) do
      run = create(:extraction_run, text_extraction: extraction, status: "running")
      rent = create(:extracted_field, extraction_run: run, position: 0, field_key: "monthly_rent", value_type: "money",
        value_integer: nil, value_amount: BigDecimal("10000"), value_currency: "BRL")
      create(:evidence_reference, extracted_field: rent, text_page: page, start_offset: 18, end_offset: 30)
      lessor = create(:extracted_field, extraction_run: run, position: 1, field_key: "lessor", value_type: "party",
        value_integer: nil, value_text: "Imobiliária Alfa Ltda.", value_tax_id: "12345678000190")
      create(:evidence_reference, extracted_field: lessor, text_page: page, start_offset: 0, end_offset: 7)
      run.update!(status: :succeeded, model_version: "fake-model-2026", field_count: 2, rejected_field_count: 1,
        input_tokens: 1000, finished_at: Time.current)
      run
    end
  end

  def request_run(version_id = version.id, request_headers: headers)
    post "/api/v1/document_versions/#{version_id}/extraction_runs", headers: request_headers
  end

  it "returns 401 when not signed in" do
    request_run

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "POST /api/v1/document_versions/:id/extraction_runs" do
      before { allow(Llm).to receive(:provider).and_return(llm) }

      it "requests a run over the latest succeeded text: 202, pending, job enqueued" do
        extraction, = succeed_text(version)

        expect { request_run }.to have_enqueued_job(ExtractContractFieldsJob).with(tenant_a.id, kind_of(String))

        expect(response).to have_http_status(:accepted)
        expect(json["data"]).to include("status" => "pending", "document_version_id" => version.id)
        expect(json["data"].keys).to contain_exactly("id", "document_version_id", "status", "field_count",
          "rejected_field_count", "error_code", "started_at", "finished_at", "created_at")
        run = with_tenant(tenant_a) { ExtractionRun.find(json["data"]["id"]) }
        expect(run).to have_attributes(requested_by_id: user.id, text_extraction_id: extraction.id)
      end

      it "answers 409 while a run is pending" do
        succeed_text(version)
        request_run

        expect { request_run }.not_to have_enqueued_job(ExtractContractFieldsJob)
        expect(response).to have_http_status(:conflict)
        expect(json.dig("error", "code")).to eq("extraction_in_progress")
      end

      it "answers 422 text_not_ready before the text extraction succeeds" do
        request_run

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("text_not_ready")
      end

      it "answers 503 extraction_unavailable when no LLM provider is configured" do
        allow(Llm).to receive(:provider).and_return(nil)
        succeed_text(version)

        request_run

        expect(response).to have_http_status(:service_unavailable)
        expect(json.dig("error", "code")).to eq("extraction_unavailable")
      end

      %w[analyst viewer].each do |reader_role|
        context "as #{reader_role}" do
          let(:role) { reader_role }

          it "is forbidden (403) and creates nothing" do
            succeed_text(version)

            expect { request_run }.not_to have_enqueued_job(ExtractContractFieldsJob)
            expect(response).to have_http_status(:forbidden)
            expect(with_tenant(tenant_a) { ExtractionRun.count }).to eq(0)
          end
        end
      end

      it "cannot request a run of another tenant's version: 404, nothing created there" do
        lease_b = with_tenant(tenant_b) { create(:lease, tenant: tenant_b) }
        version_b = upload_version(tenant_b, lease_b)
        succeed_text(version_b, tenant: tenant_b)

        request_run(version_b.id)

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { ExtractionRun.count }).to eq(0)
      end

      it "cannot target another tenant by switching X-Tenant-Id without a membership there: 403" do
        succeed_text(version)

        request_run(request_headers: { "X-Tenant-Id" => tenant_b.id })

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "the version JSON" do
      it "has extraction_run null before any run, and the latest run's summary after" do
        get "/api/v1/leases/#{lease.id}/documents", headers: headers
        expect(json["data"].first["versions"].first["extraction_run"]).to be_nil

        run = succeeded_run(version)
        get "/api/v1/leases/#{lease.id}/documents/#{version.contract_document_id}", headers: headers

        expect(json["data"]["versions"].first["extraction_run"]).to include("id" => run.id, "status" => "succeeded",
          "field_count" => 2, "rejected_field_count" => 1)
        expect(response.body).not_to include("Imobiliária Alfa")
      end
    end

    describe "GET /api/v1/extraction_runs/:id" do
      let(:role) { "viewer" }

      it "lets any member read the candidates with their evidence: money as a decimal string, snippet and source" do
        run = succeeded_run(version)

        get "/api/v1/extraction_runs/#{run.id}", headers: headers

        expect(response).to have_http_status(:ok)
        rent, lessor = json["data"]["fields"]
        expect(rent).to include("key" => "monthly_rent", "value_type" => "money",
          "value" => { "amount" => "10000.00", "currency" => "BRL" })
        expect(rent["evidence"].sole).to include("page_number" => 1, "source" => "ocr", "start_offset" => 18,
          "end_offset" => 30, "snippet" => "R$ 10.000,00")
        expect(lessor).to include("key" => "lessor", "value" => { "name" => "Imobiliária Alfa Ltda.",
          "tax_id" => "12345678000190" })
      end

      it "does not expose provider, model or token usage" do
        run = succeeded_run(version)

        get "/api/v1/extraction_runs/#{run.id}", headers: headers

        expect(json["data"].keys).not_to include("provider", "model", "model_version", "input_tokens", "prompt_version")
      end

      it "answers 404 for another tenant's run" do
        lease_b = with_tenant(tenant_b) { create(:lease, tenant: tenant_b) }
        run_b = succeeded_run(upload_version(tenant_b, lease_b), tenant: tenant_b)

        get "/api/v1/extraction_runs/#{run_b.id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("Imobiliária Alfa")
      end
    end
  end
end
