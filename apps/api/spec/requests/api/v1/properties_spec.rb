require "rails_helper"

# Request layer of the three-layer tenant isolation test, plus the
# endpoint contract documented in Api::V1::PropertiesController.
RSpec.describe "/api/v1/properties", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "manager" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let(:valid_params) do
    {
      property: {
        name: "Clínica Boa Viagem", code: "rec-01", property_type: "clinic",
        street: "Av. Boa Viagem", number: "500", city: "Recife", state: "pe",
        postal_code: "51011-000", area_sqm: "210.55"
      }
    }
  end

  def create_property(tenant, **attributes)
    with_tenant(tenant) { create(:property, tenant: tenant, **attributes) }
  end

  it "returns 401 when not signed in" do
    get "/api/v1/properties", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "GET /api/v1/properties" do
      it "lists only the current tenant's properties, paginated" do
        own = create_property(tenant_a, name: "Alpha")
        create_property(tenant_b, name: "Belongs to B")

        get "/api/v1/properties", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"].pluck("id")).to eq([ own.id ])
        expect(json["meta"]).to eq("page" => 1, "per_page" => 25, "total_count" => 1, "total_pages" => 1)
        expect(response.body).not_to include("Belongs to B")
      end

      it "paginates in name order" do
        %w[Charlie Alpha Bravo].each { |name| create_property(tenant_a, name: name) }

        get "/api/v1/properties", params: { page: 2, per_page: 2 }, headers: headers

        expect(json["data"].pluck("name")).to eq([ "Charlie" ])
        expect(json["meta"]).to include("page" => 2, "total_count" => 3, "total_pages" => 2)
      end

      it "filters by status and searches name, code or city" do
        create_property(tenant_a, name: "Loja Centro", code: "SP-1")
        create_property(tenant_a, name: "Loja Antiga", status: "archived")
        create_property(tenant_a, name: "Academia", city: "Campinas")

        get "/api/v1/properties", params: { status: "archived" }, headers: headers
        expect(json["data"].pluck("name")).to eq([ "Loja Antiga" ])

        get "/api/v1/properties", params: { q: "campinas" }, headers: headers
        expect(json["data"].pluck("name")).to eq([ "Academia" ])

        get "/api/v1/properties", params: { q: "%" }, headers: headers
        expect(json["data"]).to be_empty
      end

      it "rejects invalid pagination and filter values with 400" do
        [ { page: 0 }, { per_page: 101 }, { page: "abc" }, { status: "deleted" }, { q: [ "x" ] } ].each do |query|
          get "/api/v1/properties", params: query, headers: headers

          expect(response).to have_http_status(:bad_request), "expected 400 for #{query}"
          expect(json.dig("error", "code")).to eq("invalid_parameter")
        end
      end

      it "requires the X-Tenant-Id header" do
        get "/api/v1/properties"

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("tenant_required")
      end

      it "denies listing another tenant's properties via the header (cross-tenant)" do
        create_property(tenant_b, name: "Belongs to B")

        get "/api/v1/properties", headers: { "X-Tenant-Id" => tenant_b.id }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include("Belongs to B")
      end
    end

    describe "GET /api/v1/properties/:id" do
      it "returns the property with its address and exact area" do
        property = create_property(tenant_a, area_sqm: "152.37")

        get "/api/v1/properties/#{property.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("id" => property.id, "area_sqm" => "152.37", "status" => "active")
        expect(json.dig("data", "address")).to include("city" => "São Paulo", "state" => "SP", "postal_code" => "01310100")
        expect(json["data"]).not_to have_key("tenant_id")
      end

      it "returns 404 for another tenant's property, same as a nonexistent id (cross-tenant)" do
        other = create_property(tenant_b)

        get "/api/v1/properties/#{other.id}", headers: headers
        cross_tenant = [ response.status, response.body ]
        get "/api/v1/properties/#{SecureRandom.uuid}", headers: headers
        nonexistent = [ response.status, response.body ]

        expect(cross_tenant).to eq(nonexistent)
        expect(response).to have_http_status(:not_found)
        expect(json.dig("error", "code")).to eq("not_found")
      end

      it "returns 404 for a malformed id" do
        get "/api/v1/properties/not-a-uuid", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /api/v1/properties" do
      it "creates the property in the current tenant, normalizing input" do
        expect {
          post "/api/v1/properties", params: valid_params, headers: headers, as: :json
        }.to change { with_tenant(tenant_a) { Property.count } }.by(1)

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("code" => "REC-01", "area_sqm" => "210.55")
        expect(json.dig("data", "address")).to include("state" => "PE", "postal_code" => "51011000", "country_code" => "BR")
      end

      it "ignores a tenant_id sent in the body: the tenant comes from the membership" do
        post "/api/v1/properties", params: valid_params.deep_merge(property: { tenant_id: tenant_b.id }),
          headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(with_tenant(tenant_a) { Property.find(json.dig("data", "id")).tenant_id }).to eq(tenant_a.id)
        expect(with_tenant(tenant_b) { Property.count }).to eq(0)
      end

      it "returns 422 with per-field details for invalid input" do
        post "/api/v1/properties", params: { property: { name: "", property_type: "castle" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_failed")
        expect(json.dig("error", "details").keys).to include("name", "property_type", "street", "city", "state")
      end

      # Rails' wrap_parameters also nests known attributes sent flat, so
      # only a body with no property attribute at all is "missing".
      it "returns 400 when no property attributes are sent" do
        post "/api/v1/properties", params: { unrelated: "x" }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("parameter_missing")
      end

      context "as a viewer" do
        let(:role) { "viewer" }

        it "is forbidden and creates nothing" do
          post "/api/v1/properties", params: valid_params, headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { Property.count }).to eq(0)
        end
      end
    end

    describe "PATCH /api/v1/properties/:id" do
      let(:property) { create_property(tenant_a, name: "Old name") }

      it "updates and archives the property" do
        patch "/api/v1/properties/#{property.id}", params: { property: { name: "New name", status: "archived" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("name" => "New name", "status" => "archived")
      end

      it "returns 422 for an invalid change" do
        patch "/api/v1/properties/#{property.id}", params: { property: { area_sqm: "-3" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to have_key("area_sqm")
      end

      it "returns 404 for another tenant's property and leaves it untouched (cross-tenant)" do
        other = create_property(tenant_b, name: "B name")

        patch "/api/v1/properties/#{other.id}", params: { property: { name: "hijacked" } },
          headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { other.reload.name }).to eq("B name")
      end

      context "as an analyst" do
        let(:role) { "analyst" }

        it "is forbidden and changes nothing" do
          patch "/api/v1/properties/#{property.id}", params: { property: { name: "Changed" } },
            headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { property.reload.name }).to eq("Old name")
        end
      end
    end

    it "has no DELETE route: properties are archived" do
      property = create_property(tenant_a)

      delete "/api/v1/properties/#{property.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(with_tenant(tenant_a) { Property.exists?(property.id) }).to be(true)
    end

    it "leaves no tenant context on the connection after the request" do
      create_property(tenant_a)
      get "/api/v1/properties", headers: headers
      expect(response).to have_http_status(:ok)

      expect(current_db_setting("app.current_tenant_id")).to be_blank
      expect(Property.count).to eq(0) # RLS: no context, no rows
    end
  end
end
