require "rails_helper"

# Request layer of the three-layer isolation test for review decisions and
# the page text endpoint (docs/adr/0019), plus the contracts documented in
# Api::V1::ReviewDecisionsController and ExtractionRunPagesController.
RSpec.describe "Review decisions and page text", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "analyst" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let!(:setup_a) { setup_run(tenant_a) }
  let(:run) { setup_a[:run] }
  let(:rent) { setup_a[:rent] }

  # A succeeded run with one money field and its evidence on page 1.
  def setup_run(tenant)
    with_tenant(tenant) do
      version = create(:document_version, contract_document: create(:contract_document, tenant: tenant))
      text = create(:document_text_extraction, document_version: version)
      page = create(:document_text_page, text_extraction: text, page_number: 1, source: "ocr",
        text: "Aluguel mensal de R$ 10.000,00 pelo prazo de 60 meses.")
      text.update!(status: :succeeded, page_count: 1, native_page_count: 0, ocr_page_count: 1, finished_at: Time.current)
      run = create(:extraction_run, text_extraction: text, status: "running")
      rent = create(:extracted_field, extraction_run: run, position: 0, field_key: "monthly_rent", value_type: "money",
        value_integer: nil, value_amount: BigDecimal("10000"), value_currency: "BRL")
      create(:evidence_reference, extracted_field: rent, text_page: page, start_offset: 18, end_offset: 30)
      run.update!(status: :succeeded, model_version: "m", field_count: 1, rejected_field_count: 0, finished_at: Time.current)
      { run: run, rent: rent }
    end
  end

  def decide(field_id, body, request_headers: headers)
    post "/api/v1/extracted_fields/#{field_id}/review_decisions", params: { review_decision: body },
      headers: request_headers, as: :json
  end

  it "returns 401 when not signed in" do
    decide(rent.id, { decision: "approved" })

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "POST /api/v1/extracted_fields/:id/review_decisions" do
      it "records a correction: 201 with the corrected value as a decimal string" do
        decide(rent.id, { decision: "corrected", value: { amount: "18500.00", currency: "BRL" }, reason: "Aditivo de 2025" })

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("extracted_field_id" => rent.id, "decision" => "corrected",
          "value" => { "amount" => "18500.00", "currency" => "BRL" }, "reason" => "Aditivo de 2025",
          "reviewed_by" => { "id" => user.id, "full_name" => user.full_name })
      end

      it "shows the latest decision on the run, with the review summary" do
        decide(rent.id, { decision: "rejected" })
        decide(rent.id, { decision: "approved" })

        get "/api/v1/extraction_runs/#{run.id}", headers: headers

        field = json["data"]["fields"].sole
        expect(field["review"]).to include("decision" => "approved", "value" => nil)
        expect(field["review_count"]).to eq(2)
        expect(json["data"]["review_summary"]).to eq("approved" => 1, "corrected" => 0, "rejected" => 0, "pending" => 0)
        expect(json["data"]["document_version"]).to include("id" => run.document_version_id,
          "content_type" => "application/pdf", "original_filename" => "contrato.pdf")
      end

      it "answers 422 for an invalid correction" do
        decide(rent.id, { decision: "corrected", value: { amount: "18.500,00", currency: "BRL" } })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details", "value")).to be_present
      end

      it "answers 409 stale_run for a field of an older run" do
        with_tenant(tenant_a) do
          newer = create(:extraction_run, text_extraction: run.text_extraction, status: "running")
          newer.update!(status: :succeeded, model_version: "m", field_count: 0, rejected_field_count: 0,
            finished_at: Time.current)
        end

        decide(rent.id, { decision: "approved" })

        expect(response).to have_http_status(:conflict)
        expect(json.dig("error", "code")).to eq("stale_run")
      end

      context "as viewer" do
        let(:role) { "viewer" }

        it "is forbidden (403) and records nothing" do
          decide(rent.id, { decision: "approved" })

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { ReviewDecision.count }).to eq(0)
        end
      end

      it "cannot decide on another tenant's field: 404, nothing recorded there" do
        field_b = setup_run(tenant_b)[:rent]

        decide(field_b.id, { decision: "approved" })

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { ReviewDecision.count }).to eq(0)
      end
    end

    describe "GET /api/v1/extraction_runs/:id/pages/:page_number" do
      let(:role) { "viewer" }

      it "returns the full page text the evidence offsets point into" do
        get "/api/v1/extraction_runs/#{run.id}/pages/1", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to eq("page_number" => 1, "source" => "ocr",
          "text" => "Aluguel mensal de R$ 10.000,00 pelo prazo de 60 meses.")
        expect(json["data"]["text"][18...30]).to eq("R$ 10.000,00")
      end

      it "answers 404 for a page the run does not have, and for another tenant's run" do
        run_b = setup_run(tenant_b)[:run]

        get "/api/v1/extraction_runs/#{run.id}/pages/2", headers: headers
        expect(response).to have_http_status(:not_found)

        get "/api/v1/extraction_runs/#{run_b.id}/pages/1", headers: headers
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("Aluguel")
      end
    end
  end
end
