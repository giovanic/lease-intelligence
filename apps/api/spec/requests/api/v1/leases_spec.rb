require "rails_helper"

# Request layer of the three-layer tenant isolation test, plus the
# endpoint contract documented in Api::V1::LeasesController.
RSpec.describe "/api/v1/leases", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "manager" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let!(:property) { with_tenant(tenant_a) { create(:property, tenant: tenant_a, name: "Clínica Centro") } }
  let!(:lessor) { with_tenant(tenant_a) { create(:counterparty, tenant: tenant_a, legal_name: "Imobiliária Alfa Ltda") } }
  let!(:guarantor) { with_tenant(tenant_a) { create(:counterparty, :individual, tenant: tenant_a) } }
  let(:valid_params) do
    {
      lease: {
        title: "Locação Clínica Centro", code: "loc-2024-01", status: "active", notes: "Contrato original",
        property_id: property.id,
        parties: [ { counterparty_id: lessor.id, role: "lessor" }, { counterparty_id: guarantor.id, role: "guarantor" } ]
      }
    }
  end

  def create_lease(tenant, **attributes)
    with_tenant(tenant) { create(:lease, :with_lessor, tenant: tenant, **attributes) }
  end

  it "returns 401 when not signed in" do
    get "/api/v1/leases", headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "GET /api/v1/leases" do
      it "lists only the current tenant's leases, paginated" do
        own = create_lease(tenant_a, title: "Alpha")
        create_lease(tenant_b, title: "Belongs to B")

        get "/api/v1/leases", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"].pluck("id")).to eq([ own.id ])
        expect(json["meta"]).to eq("page" => 1, "per_page" => 25, "total_count" => 1, "total_pages" => 1)
        expect(response.body).not_to include("Belongs to B")
      end

      it "paginates in title order" do
        %w[Charlie Alpha Bravo].each { |title| create_lease(tenant_a, title: title) }

        get "/api/v1/leases", params: { page: 2, per_page: 2 }, headers: headers

        expect(json["data"].pluck("title")).to eq([ "Charlie" ])
        expect(json["meta"]).to include("page" => 2, "total_count" => 3, "total_pages" => 2)
      end

      it "filters by status, property, counterparty and searches title or code" do
        other_property = with_tenant(tenant_a) { create(:property, tenant: tenant_a) }
        create_lease(tenant_a, title: "Loja Centro", code: "LOC-1", property: property)
        create_lease(tenant_a, title: "Loja Antiga", status: "terminated", property: other_property)
        with_tenant(tenant_a) { create(:lease_party, lease: create(:lease, tenant: tenant_a, title: "Com fiador"), counterparty: guarantor) }

        get "/api/v1/leases", params: { status: "terminated" }, headers: headers
        expect(json["data"].pluck("title")).to eq([ "Loja Antiga" ])

        get "/api/v1/leases", params: { property_id: property.id }, headers: headers
        expect(json["data"].pluck("title")).to eq([ "Loja Centro" ])

        get "/api/v1/leases", params: { counterparty_id: guarantor.id }, headers: headers
        expect(json["data"].pluck("title")).to eq([ "Com fiador" ])

        get "/api/v1/leases", params: { q: "loc-1" }, headers: headers
        expect(json["data"].pluck("title")).to eq([ "Loja Centro" ])

        get "/api/v1/leases", params: { q: "%" }, headers: headers
        expect(json["data"]).to be_empty
      end

      it "finds nothing when filtering by another tenant's property or counterparty" do
        foreign = create_lease(tenant_b)

        get "/api/v1/leases", params: { property_id: foreign.property_id }, headers: headers
        expect(json["data"]).to be_empty

        get "/api/v1/leases", params: { counterparty_id: foreign.lease_parties.first.counterparty_id }, headers: headers
        expect(json["data"]).to be_empty
      end

      it "rejects invalid pagination and filter values with 400" do
        [ { page: 0 }, { per_page: 101 }, { status: "cancelled" }, { property_id: "abc" },
          { counterparty_id: [ "x" ] }, { q: [ "x" ] } ].each do |query|
          get "/api/v1/leases", params: query, headers: headers

          expect(response).to have_http_status(:bad_request), "expected 400 for #{query}"
          expect(json.dig("error", "code")).to eq("invalid_parameter")
        end
      end

      it "does not issue more queries as the number of leases grows (no N+1)" do
        create_lease(tenant_a)
        get "/api/v1/leases", headers: headers
        single = count_queries { get "/api/v1/leases", headers: headers }

        2.times { create_lease(tenant_a) }
        triple = count_queries { get "/api/v1/leases", headers: headers }

        expect(json["data"].size).to eq(3)
        expect(triple).to eq(single)
      end

      it "denies listing another tenant's leases via the header (cross-tenant)" do
        create_lease(tenant_b, title: "Belongs to B")

        get "/api/v1/leases", headers: { "X-Tenant-Id" => tenant_b.id }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include("Belongs to B")
      end
    end

    describe "GET /api/v1/leases/:id" do
      it "returns the lease with its property and parties, without counterparty personal data" do
        lease = create_lease(tenant_a, property: property, code: "LOC-9")

        get "/api/v1/leases/#{lease.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("id" => lease.id, "code" => "LOC-9", "status" => "active")
        expect(json.dig("data", "property")).to include("id" => property.id, "name" => "Clínica Centro")
        party = json.dig("data", "parties", 0)
        expect(party).to include("role" => "lessor")
        expect(party["counterparty"].keys).to contain_exactly("id", "kind", "legal_name", "trade_name")
        expect(json["data"]).not_to have_key("tenant_id")
      end

      it "returns 404 for another tenant's lease, same as a nonexistent id (cross-tenant)" do
        other = create_lease(tenant_b)

        get "/api/v1/leases/#{other.id}", headers: headers
        cross_tenant = [ response.status, response.body ]
        get "/api/v1/leases/#{SecureRandom.uuid}", headers: headers
        nonexistent = [ response.status, response.body ]

        expect(cross_tenant).to eq(nonexistent)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /api/v1/leases" do
      it "creates the lease with its parties in the current tenant" do
        expect {
          post "/api/v1/leases", params: valid_params, headers: headers, as: :json
        }.to change { with_tenant(tenant_a) { [ Lease.count, LeaseParty.count ] } }.from([ 0, 0 ]).to([ 1, 2 ])

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("title" => "Locação Clínica Centro", "code" => "LOC-2024-01", "status" => "active")
        expect(json.dig("data", "parties").map { |party| [ party.dig("counterparty", "id"), party["role"] ] })
          .to eq([ [ lessor.id, "lessor" ], [ guarantor.id, "guarantor" ] ])
      end

      it "ignores a tenant_id sent in the body: the tenant comes from the membership" do
        post "/api/v1/leases", params: valid_params.deep_merge(lease: { tenant_id: tenant_b.id }), headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(with_tenant(tenant_a) { Lease.find(json.dig("data", "id")).tenant_id }).to eq(tenant_a.id)
        expect(with_tenant(tenant_b) { Lease.count }).to eq(0)
      end

      it "returns 422 when the property or a counterparty belongs to another tenant (cross-tenant)" do
        foreign_property = with_tenant(tenant_b) { create(:property, tenant: tenant_b) }
        foreign_counterparty = with_tenant(tenant_b) { create(:counterparty, tenant: tenant_b) }
        params = valid_params.deep_merge(lease: {
          property_id: foreign_property.id, parties: [ { counterparty_id: foreign_counterparty.id, role: "lessor" } ]
        })

        post "/api/v1/leases", params: params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to eq(
          "property_id" => [ "not found" ], "parties[0].counterparty_id" => [ "not found" ]
        )
        expect(with_tenant(tenant_a) { Lease.count }).to eq(0)
      end

      it "returns 422 with per-field details for invalid input" do
        post "/api/v1/leases", params: { lease: { title: "", status: "cancelled" } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_failed")
        expect(json.dig("error", "details").keys).to contain_exactly("title", "status", "property_id", "parties")
      end

      it "returns 400 when no lease attributes are sent" do
        post "/api/v1/leases", params: { unrelated: "x" }, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("parameter_missing")
      end

      context "as a viewer" do
        let(:role) { "viewer" }

        it "is forbidden and creates nothing" do
          post "/api/v1/leases", params: valid_params, headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { Lease.count }).to eq(0)
        end
      end
    end

    describe "PATCH /api/v1/leases/:id" do
      let(:lease) { create_lease(tenant_a, title: "Old title", property: property) }

      it "updates the lease and replaces its parties" do
        patch "/api/v1/leases/#{lease.id}",
          params: { lease: { title: "New title", status: "terminated", parties: [ { counterparty_id: guarantor.id, role: "lessor" } ] } },
          headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("title" => "New title", "status" => "terminated")
        expect(json.dig("data", "parties").map { |party| party.dig("counterparty", "id") }).to eq([ guarantor.id ])
      end

      it "keeps the parties when they are not sent" do
        patch "/api/v1/leases/#{lease.id}", params: { lease: { notes: "Atualizado" } }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "parties").size).to eq(1)
      end

      it "returns 422 for an empty party list" do
        patch "/api/v1/leases/#{lease.id}", params: { lease: { parties: [] } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to eq("parties" => [ "must include at least one lessor" ])
      end

      it "returns 422 when changing the property of a lease that is no longer a draft" do
        other_property = with_tenant(tenant_a) { create(:property, tenant: tenant_a) }

        patch "/api/v1/leases/#{lease.id}", params: { lease: { property_id: other_property.id } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details")).to have_key("property_id")
      end

      it "returns 404 for another tenant's lease and leaves it untouched (cross-tenant)" do
        other = create_lease(tenant_b, title: "B title")

        patch "/api/v1/leases/#{other.id}", params: { lease: { title: "hijacked" } }, headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { other.reload.title }).to eq("B title")
      end

      context "as an analyst" do
        let(:role) { "analyst" }

        it "is forbidden and changes nothing" do
          patch "/api/v1/leases/#{lease.id}", params: { lease: { title: "Changed" } }, headers: headers, as: :json

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { lease.reload.title }).to eq("Old title")
        end
      end
    end

    it "has no DELETE route: leases end through their status" do
      lease = create_lease(tenant_a)

      delete "/api/v1/leases/#{lease.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(with_tenant(tenant_a) { Lease.exists?(lease.id) }).to be(true)
    end

    it "leaves no tenant context on the connection after the request" do
      create_lease(tenant_a)
      get "/api/v1/leases", headers: headers
      expect(response).to have_http_status(:ok)

      expect(current_db_setting("app.current_tenant_id")).to be_blank
      expect([ Lease.count, LeaseParty.count ]).to eq([ 0, 0 ]) # RLS: no context, no rows
    end
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].include?("set_config") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
