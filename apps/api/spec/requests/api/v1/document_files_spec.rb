require "rails_helper"

# The file access path of docs/adr/0015: a link issued after authorization,
# then the bytes served only for that link + the same user's session + a
# live membership + RLS + Pundit.
RSpec.describe "Document download links and files", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "viewer" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let(:bytes) { unique_pdf_bytes }
  let!(:version) { create_version(tenant_a, uploaded_file(bytes, filename: "Contrato Loja Centro.pdf")) }

  def create_version(tenant, file = uploaded_file)
    with_tenant(tenant) do
      lease = create(:lease, tenant: tenant)
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "original_contract", title: "C" },
        file: file).value.versions.sole
    end
  end

  def issue_link(version_id = version.id)
    post "/api/v1/document_versions/#{version_id}/download_link", headers: headers
  end

  it "returns 401 for both steps when not signed in" do
    issue_link
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/document_files/#{Documents::DownloadLink.issue(version: version, user: user).token}"
    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "issues a 5-minute link that serves the exact bytes inline, uncached" do
      issue_link

      expect(response).to have_http_status(:created)
      url = json.dig("data", "url")
      expect(url).to start_with("/api/v1/document_files/")
      expect(Time.zone.parse(json.dig("data", "expires_at"))).to be_within(2.seconds).of(5.minutes.from_now)

      get url

      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(bytes)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to start_with(%(inline; filename="Contrato Loja Centro.pdf"))
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "keeps the original filename out of the request log" do
      issue_link
      url = json.dig("data", "url")
      sent = []
      subscriber = ActiveSupport::Notifications.subscribe("send_data.action_controller") { |event| sent << event.payload }

      get url

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(sent.sole[:filename]).to be_nil # what LogSubscriber prints as "Sent data <filename>"
      expect(response.headers["Content-Disposition"]).to include("Contrato Loja Centro.pdf")
    end

    it "does not issue a link for another tenant's version" do
      other = create_version(tenant_b)

      issue_link(other.id)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses the link for another signed-in user, even a member of the same tenant" do
      issue_link
      url = json.dig("data", "url")
      colleague = create(:user)
      with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: colleague, role: "owner") }

      sign_in_as(colleague)
      get url

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an expired link" do
      issue_link
      url = json.dig("data", "url")

      travel 5.minutes + 1.second do
        get url
      end

      expect(response).to have_http_status(:not_found)
    end

    it "refuses the link once the membership is suspended" do
      issue_link
      url = json.dig("data", "url")
      with_tenant(tenant_a) { membership.update!(status: "suspended") }

      get url

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a tampered token and one pointing at another tenant's version" do
      get "/api/v1/document_files/not-a-token"
      expect(response).to have_http_status(:not_found)

      # Even a validly signed token cannot reach a version RLS hides in the token's tenant.
      other = create_version(tenant_b)
      forged = Documents::DownloadLink.issue(version: other, user: user).token
      get "/api/v1/document_files/#{forged}"
      expect(response).to have_http_status(:not_found)
    end

    it "answers 503 when the stored file cannot be read" do
      issue_link
      url = json.dig("data", "url")
      ActiveStorage::Blob.service.delete(version.storage_key)

      get url

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig("error", "code")).to eq("storage_unavailable")
    end
  end
end
