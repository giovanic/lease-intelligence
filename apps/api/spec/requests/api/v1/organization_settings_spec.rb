require "rails_helper"

# Per-organization AI consent (docs/adr/0018): the settings endpoint, and
# its effect on AI field extraction requests.
RSpec.describe "/api/v1/organization_settings", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "owner" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }

  def update_settings(enabled, request_headers: headers)
    patch "/api/v1/organization_settings", params: { organization_settings: { ai_extraction_enabled: enabled } },
      headers: request_headers, as: :json
  end

  it "returns 401 when not signed in" do
    get "/api/v1/organization_settings", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "starts with AI extraction off for a new organization, and says which provider is configured" do
      allow(Llm).to receive(:provider).and_return(FieldExtractionHelpers::FakeLlm.new(external: false))

      get "/api/v1/organization_settings", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq("ai_extraction_enabled" => false, "ai_extraction_changed_at" => nil,
        "ai_extraction_changed_by" => nil,
        "ai_provider" => { "name" => "fake", "model" => "fake-model", "external" => false })
    end

    it "reports no provider when none is configured" do
      get "/api/v1/organization_settings", headers: headers

      expect(json["data"]["ai_provider"]).to be_nil
    end

    %w[owner admin].each do |manager_role|
      context "as #{manager_role}" do
        let(:role) { manager_role }

        it "turns AI extraction on, recording who and when, and off again" do
          update_settings(true)

          expect(response).to have_http_status(:ok)
          expect(json["data"]).to include("ai_extraction_enabled" => true,
            "ai_extraction_changed_by" => { "id" => user.id, "full_name" => user.full_name })
          expect(tenant_a.reload).to have_attributes(ai_extraction_enabled: true, ai_extraction_changed_by_id: user.id)
          expect(tenant_a.ai_extraction_changed_at).to be_within(1.minute).of(Time.current)

          update_settings(false)

          expect(tenant_a.reload.ai_extraction_enabled).to be(false)
        end
      end
    end

    %w[manager analyst viewer].each do |other_role|
      context "as #{other_role}" do
        let(:role) { other_role }

        it "can read the settings but not change them (403)" do
          get "/api/v1/organization_settings", headers: headers
          expect(response).to have_http_status(:ok)

          update_settings(true)

          expect(response).to have_http_status(:forbidden)
          expect(tenant_a.reload.ai_extraction_enabled).to be(false)
        end
      end
    end

    it "accepts only a JSON boolean (422 otherwise)" do
      [ "true", 1, nil ].each do |value|
        update_settings(value)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details", "ai_extraction_enabled")).to be_present
      end
      expect(tenant_a.reload.ai_extraction_enabled).to be(false)
    end

    it "cannot change another organization: X-Tenant-Id without a membership is 403, and body ids are ignored" do
      update_settings(true, request_headers: { "X-Tenant-Id" => tenant_b.id })
      expect(response).to have_http_status(:forbidden)

      patch "/api/v1/organization_settings", headers: headers, as: :json,
        params: { organization_settings: { ai_extraction_enabled: true, tenant_id: tenant_b.id, id: tenant_b.id } }

      expect(tenant_a.reload.ai_extraction_enabled).to be(true)
      expect(tenant_b.reload.ai_extraction_enabled).to be(false)
    end

    it "exposes the flag on the current membership, for the SPA" do
      tenant_a.update!(ai_extraction_enabled: true, ai_extraction_changed_at: Time.current,
        ai_extraction_changed_by: user)

      get "/api/v1/current_membership", headers: headers

      expect(json.dig("data", "tenant", "ai_extraction_enabled")).to be(true)
    end

    describe "effect on AI field extraction requests" do
      let(:role) { "manager" }
      let!(:lease) { with_tenant(tenant_a) { create(:lease, tenant: tenant_a) } }
      let!(:version) do
        with_tenant(tenant_a, user: user) do
          Documents::CreateDocument.call(lease: lease, uploaded_by: user,
            attributes: { kind: "original_contract", title: "Contrato" }, file: uploaded_file).value.versions.first
        end
      end

      before do
        allow(Llm).to receive(:provider).and_return(FieldExtractionHelpers::FakeLlm.new)
        with_tenant(tenant_a) do
          extraction = version.reload.latest_text_extraction
          create(:document_text_page, text_extraction: extraction, page_number: 1, text: "Prazo de 60 meses")
          extraction.update!(status: :succeeded, page_count: 1, native_page_count: 1, ocr_page_count: 0,
            finished_at: Time.current)
        end
      end

      it "answers 422 extraction_disabled while the organization has not turned it on" do
        expect { post "/api/v1/document_versions/#{version.id}/extraction_runs", headers: headers }
          .not_to have_enqueued_job(ExtractContractFieldsJob)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("extraction_disabled")
        expect(with_tenant(tenant_a) { ExtractionRun.count }).to eq(0)
      end
    end
  end
end
