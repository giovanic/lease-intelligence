require "rails_helper"

RSpec.describe "Sign-in throttling (Rack::Attack)", type: :request do
  # The test environment uses :null_store for Rails.cache, which would
  # make every throttle a no-op; give Rack::Attack a real store here only.
  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original_store
  end

  def attempt(email, ip: "10.0.0.1")
    post "/api/v1/session", params: { email: email, password: "wrong" }, as: :json,
      headers: { "REMOTE_ADDR" => ip }
  end

  it "throttles repeated attempts against the same email, even from different IPs" do
    5.times { |i| attempt("target@example.com", ip: "10.0.0.#{i + 1}") }
    expect(response).to have_http_status(:unauthorized)

    attempt("TARGET@example.com", ip: "10.0.0.99")

    expect(response).to have_http_status(:too_many_requests)
    expect(json.dig("error", "code")).to eq("too_many_requests")
    expect(response.headers["retry-after"]).to eq("60")
  end

  it "throttles repeated attempts from the same IP across different emails" do
    10.times { |i| attempt("user#{i}@example.com") }
    expect(response).to have_http_status(:unauthorized)

    attempt("another@example.com")

    expect(response).to have_http_status(:too_many_requests)
  end
end
