require "rails_helper"

RSpec.describe "GET /api/v1/me", type: :request do
  let(:user) { create(:user) }
  let(:tenant) { create(:tenant) }

  before { with_tenant(tenant) { create(:membership, tenant: tenant, user: user, role: "viewer") } }

  it "returns 401 in the standard error envelope when not signed in" do
    get "/api/v1/me"

    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("unauthenticated")
  end

  it "returns the user and only their own memberships" do
    stranger = create(:user)
    with_tenant(tenant) { create(:membership, tenant: tenant, user: stranger) }
    sign_in_as(user)

    get "/api/v1/me"

    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "user", "id")).to eq(user.id)
    memberships = json.dig("data", "memberships")
    expect(memberships.size).to eq(1)
    expect(memberships.first).to include("role" => "viewer", "status" => "active")
  end

  it "expires an idle session server-side (Devise :timeoutable)" do
    sign_in_as(user)

    travel(Devise.timeout_in + 1.minute) do
      get "/api/v1/me"
    end

    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("unauthenticated")
  end
end
