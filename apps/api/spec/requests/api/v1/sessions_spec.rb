require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, email: "ana@example.com") }
  let(:tenant) { create(:tenant, name: "Rede Saúde") }

  before { with_tenant(tenant) { create(:membership, tenant: tenant, user: user, role: "admin") } }

  describe "POST /api/v1/session" do
    it "signs in, sets an httpOnly SameSite=Lax cookie and returns the user with selectable memberships" do
      post "/api/v1/session", params: { email: "ANA@example.com", password: "password123!" }, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "user")).to eq("id" => user.id, "email" => "ana@example.com", "full_name" => "Test User")
      expect(json.dig("data", "memberships").map { |m| m.dig("tenant", "id") }).to eq([ tenant.id ])
      expect(json.dig("data", "memberships", 0, "role")).to eq("admin")

      cookie = response.headers["set-cookie"].to_s
      expect(cookie).to include("_lease_intelligence_session=")
      expect(cookie).to match(/httponly/i)
      expect(cookie).to match(/samesite=lax/i)
    end

    it "never exposes Devise internals" do
      post "/api/v1/session", params: { email: user.email, password: "password123!" }, as: :json

      expect(response.body).not_to include("encrypted_password", "current_sign_in_ip")
    end

    it "answers the same 401 for a wrong password and for an unknown email" do
      post "/api/v1/session", params: { email: user.email, password: "wrong-password" }, as: :json
      wrong_password = [ response.status, response.body ]

      post "/api/v1/session", params: { email: "nobody@example.com", password: "wrong-password" }, as: :json
      unknown_email = [ response.status, response.body ]

      expect(wrong_password).to eq(unknown_email)
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_credentials")
    end

    it "returns 400 when a credential is missing" do
      post "/api/v1/session", params: { email: user.email }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("parameter_missing")
    end

    it "does not list memberships in suspended tenants or suspended memberships" do
      suspended_tenant = create(:tenant, status: "suspended")
      other_tenant = create(:tenant)
      with_tenant(suspended_tenant) { create(:membership, tenant: suspended_tenant, user: user) }
      with_tenant(other_tenant) { create(:membership, tenant: other_tenant, user: user, status: "suspended") }

      sign_in_as(user)

      expect(json.dig("data", "memberships").map { |m| m.dig("tenant", "id") }).to eq([ tenant.id ])
    end

    describe "CSRF protection (ADR-0013)" do
      it "rejects a sign-in coming from a foreign Origin" do
        post "/api/v1/session", params: { email: user.email, password: "password123!" }, as: :json,
          headers: { "Origin" => "https://evil.example" }

        expect(response).to have_http_status(:forbidden)
        expect(json.dig("error", "code")).to eq("cross_site_request")
      end

      it "rejects Sec-Fetch-Site: cross-site even without an Origin" do
        post "/api/v1/session", params: { email: user.email, password: "password123!" }, as: :json,
          headers: { "Sec-Fetch-Site" => "cross-site" }

        expect(response).to have_http_status(:forbidden)
      end

      it "accepts the API's own origin" do
        post "/api/v1/session", params: { email: user.email, password: "password123!" }, as: :json,
          headers: { "Origin" => "http://www.example.com" }

        expect(response).to have_http_status(:created)
      end

      it "rejects a form-encoded body (what a cross-site HTML form would send)" do
        post "/api/v1/session", params: { email: user.email, password: "password123!" }

        expect(response).to have_http_status(:unsupported_media_type)
      end
    end
  end

  describe "DELETE /api/v1/session" do
    it "signs out, after which the session no longer authenticates" do
      sign_in_as(user)

      delete "/api/v1/session"
      expect(response).to have_http_status(:no_content)

      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 when not signed in" do
      delete "/api/v1/session"

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("unauthenticated")
    end
  end
end
