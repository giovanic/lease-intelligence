require "rails_helper"

# Request layer of the three-layer tenant isolation test, plus the
# endpoint contract documented in Api::V1::CounterpartiesController.
RSpec.describe "/api/v1/counterparties", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "admin" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let(:valid_params) do
    {
      counterparty: {
        kind: "company", legal_name: "Imobiliária Recife Ltda", trade_name: "Recife Imóveis",
        tax_id: "11.222.333/0001-81", email: "Contato@RecifeImoveis.com.br", phone: "+55 81 3333-0000"
      }
    }
  end

  def create_counterparty(tenant, *traits, **attributes)
    with_tenant(tenant) { create(:counterparty, *traits, tenant: tenant, **attributes) }
  end

  it "returns 401 when not signed in" do
    get "/api/v1/counterparties", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "GET /api/v1/counterparties" do
      it "lists only the current tenant's counterparties" do
        own = create_counterparty(tenant_a, legal_name: "Alpha Locações")
        create_counterparty(tenant_b, legal_name: "Belongs to B")

        get "/api/v1/counterparties", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"].pluck("id")).to eq([ own.id ])
        expect(json["meta"]).to include("total_count" => 1)
        expect(response.body).not_to include("Belongs to B")
      end

      it "filters by kind and status and searches name or formatted tax id" do
        create_counterparty(tenant_a, legal_name: "Empresa Ativa", tax_id: "11222333000181")
        create_counterparty(tenant_a, :individual, legal_name: "Maria Locadora", tax_id: "52998224725")
        create_counterparty(tenant_a, legal_name: "Empresa Antiga", status: "archived")

        get "/api/v1/counterparties", params: { kind: "individual" }, headers: headers
        expect(json["data"].pluck("legal_name")).to eq([ "Maria Locadora" ])

        get "/api/v1/counterparties", params: { status: "archived" }, headers: headers
        expect(json["data"].pluck("legal_name")).to eq([ "Empresa Antiga" ])

        get "/api/v1/counterparties", params: { q: "11.222.333/0001" }, headers: headers
        expect(json["data"].pluck("legal_name")).to eq([ "Empresa Ativa" ])

        get "/api/v1/counterparties", params: { q: "maria" }, headers: headers
        expect(json["data"].pluck("legal_name")).to eq([ "Maria Locadora" ])
      end

      it "rejects an unknown kind with 400" do
        get "/api/v1/counterparties", params: { kind: "trust" }, headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("invalid_parameter")
      end

      it "denies listing another tenant's counterparties via the header (cross-tenant)" do
        get "/api/v1/counterparties", headers: { "X-Tenant-Id" => tenant_b.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /api/v1/counterparties/:id" do
      it "returns the counterparty" do
        counterparty = create_counterparty(tenant_a, :individual, tax_id: "52998224725")

        get "/api/v1/counterparties/#{counterparty.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("id" => counterparty.id, "kind" => "individual", "tax_id" => "52998224725")
        expect(json["data"]).not_to have_key("tenant_id")
      end

      it "returns 404 for another tenant's counterparty (cross-tenant)" do
        other = create_counterparty(tenant_b)

        get "/api/v1/counterparties/#{other.id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(other.legal_name)
      end
    end

    describe "POST /api/v1/counterparties" do
      it "creates the counterparty in the current tenant, normalizing tax id and email" do
        post "/api/v1/counterparties", params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include(
          "tax_id" => "11222333000181", "email" => "contato@recifeimoveis.com.br", "status" => "active"
        )
        expect(with_tenant(tenant_a) { Counterparty.find(json.dig("data", "id")).tenant_id }).to eq(tenant_a.id)
      end

      it "allows the same tax id in another tenant but not twice in one" do
        create_counterparty(tenant_b, tax_id: "11222333000181")

        post "/api/v1/counterparties", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:created)

        post "/api/v1/counterparties", params: valid_params, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to have_key("tax_id")
      end

      it "returns 422 for a CPF with a wrong check digit" do
        post "/api/v1/counterparties",
          params: { counterparty: { kind: "individual", legal_name: "João", tax_id: "529.982.247-24" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details", "tax_id")).to eq([ "is not a valid CPF" ])
      end

      it "does not write the tax id or phone to the log" do
        log = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log)
        begin
          post "/api/v1/counterparties", params: valid_params, headers: headers, as: :json
        ensure
          Rails.logger = original_logger
        end

        expect(response).to have_http_status(:created)
        expect(log.string).not_to include("11.222.333/0001-81", "11222333000181", "3333-0000")
      end

      context "as a viewer" do
        let(:role) { "viewer" }

        it "is forbidden and creates nothing" do
          post "/api/v1/counterparties", params: valid_params, headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { Counterparty.count }).to eq(0)
        end
      end
    end

    describe "PATCH /api/v1/counterparties/:id" do
      let(:counterparty) { create_counterparty(tenant_a, legal_name: "Nome Antigo") }

      it "updates and archives the counterparty" do
        patch "/api/v1/counterparties/#{counterparty.id}",
          params: { counterparty: { legal_name: "Nome Novo", status: "archived" } }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("legal_name" => "Nome Novo", "status" => "archived")
      end

      it "returns 404 for another tenant's counterparty and leaves it untouched (cross-tenant)" do
        other = create_counterparty(tenant_b, legal_name: "Nome B")

        patch "/api/v1/counterparties/#{other.id}", params: { counterparty: { legal_name: "hijacked" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { other.reload.legal_name }).to eq("Nome B")
      end

      context "as an analyst" do
        let(:role) { "analyst" }

        it "is forbidden and changes nothing" do
          patch "/api/v1/counterparties/#{counterparty.id}", params: { counterparty: { legal_name: "X" } },
            headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { counterparty.reload.legal_name }).to eq("Nome Antigo")
        end
      end
    end
  end
end
