require "rails_helper"

# Request layer of the three-layer tenant isolation test
# (docs/runbooks/testing.md): the TenantScoped concern end to end.
RSpec.describe "GET /api/v1/current_membership", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant, name: "Tenant A") }
  let(:tenant_b) { create(:tenant, name: "Tenant B") }
  let!(:membership_a) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: "manager") } }

  before do
    other_user = create(:user)
    with_tenant(tenant_b) { create(:membership, tenant: tenant_b, user: other_user, role: "owner") }
  end

  def get_current_membership(tenant_id)
    headers = tenant_id ? { "X-Tenant-Id" => tenant_id } : {}
    get "/api/v1/current_membership", headers: headers
  end

  it "returns 401 when not signed in, even with a valid tenant header" do
    get_current_membership(tenant_a.id)

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "returns the caller's membership for a tenant they belong to" do
      get_current_membership(tenant_a.id)

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("id" => membership_a.id, "role" => "manager")
      expect(json.dig("data", "tenant", "id")).to eq(tenant_a.id)
    end

    it "returns 400 when the X-Tenant-Id header is missing" do
      get_current_membership(nil)

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("tenant_required")
    end

    it "denies another tenant's id (cross-tenant attempt) with 403" do
      get_current_membership(tenant_b.id)

      expect(response).to have_http_status(:forbidden)
      expect(json.dig("error", "code")).to eq("tenant_forbidden")
      expect(response.body).not_to include("Tenant B")
    end

    it "gives the same 403 for a nonexistent and a malformed tenant id" do
      get_current_membership(SecureRandom.uuid)
      nonexistent = [ response.status, response.body ]

      get_current_membership("1 OR 1=1")
      malformed = [ response.status, response.body ]

      expect(nonexistent).to eq(malformed)
      expect(response).to have_http_status(:forbidden)
    end

    it "denies a suspended membership" do
      with_tenant(tenant_a) { membership_a.update!(status: "suspended") }

      get_current_membership(tenant_a.id)

      expect(response).to have_http_status(:forbidden)
    end

    it "denies a membership in a tenant that is no longer active" do
      tenant_a.update!(status: "suspended")

      get_current_membership(tenant_a.id)

      expect(response).to have_http_status(:forbidden)
    end

    describe "connection pool safety" do
      it "leaves no tenant or user context on the connection after the request" do
        get_current_membership(tenant_a.id)
        expect(response).to have_http_status(:ok)

        expect(current_db_setting("app.current_tenant_id")).to be_blank
        expect(current_db_setting("app.current_user_id")).to be_blank
        expect(Membership.count).to eq(0) # RLS: no context, no rows
        expect(Current.tenant).to be_nil
      end

      it "does not carry tenant A's context into a following request for tenant B" do
        get_current_membership(tenant_a.id)
        expect(response).to have_http_status(:ok)

        get_current_membership(tenant_b.id)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
