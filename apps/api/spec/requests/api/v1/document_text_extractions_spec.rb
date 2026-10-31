require "rails_helper"

# Request layer of the three-layer tenant isolation test for text
# extractions (docs/adr/0016), plus the contract documented in
# Api::V1::DocumentTextExtractionsController and the `text_extraction`
# field of the version JSON.
RSpec.describe "/api/v1/document_versions/:id/text_extractions", type: :request do
  let(:user) { create(:user) }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "manager" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let!(:lease) { with_tenant(tenant_a) { create(:lease, tenant: tenant_a) } }
  let!(:version) { upload_version(tenant_a, lease) }

  def upload_version(tenant, lease)
    with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "amendment", title: "Aditivo" },
        file: uploaded_file).value.versions.first
    end
  end

  def latest_extraction(version, tenant: tenant_a)
    with_tenant(tenant) { version.reload.latest_text_extraction }
  end

  def finish(extraction, tenant: tenant_a)
    with_tenant(tenant) { extraction.update!(status: :failed, error_code: "unreadable_file", finished_at: Time.current) }
  end

  def reprocess(version_id = version.id, request_headers: headers)
    post "/api/v1/document_versions/#{version_id}/text_extractions", headers: request_headers
  end

  it "returns 401 when not signed in" do
    reprocess

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    it "starts with the pending extraction every upload requests, shown on the version" do
      get "/api/v1/leases/#{lease.id}/documents", headers: headers

      extraction = json["data"].first["versions"].first["text_extraction"]
      expect(extraction).to include("id" => latest_extraction(version).id, "document_version_id" => version.id,
        "status" => "pending", "page_count" => nil, "error_code" => nil)
      expect(extraction.keys).to contain_exactly("id", "document_version_id", "status", "page_count",
        "native_page_count", "ocr_page_count", "error_code", "started_at", "finished_at", "created_at")
    end

    it "shows the counts of a succeeded extraction, never its text" do
      extraction = latest_extraction(version) # outside: with_tenant does not nest
      with_tenant(tenant_a) do
        create(:document_text_page, text_extraction: extraction, page_number: 1, text: "Aluguel de R$ 10.000,00")
        extraction.update!(status: :succeeded, page_count: 1, native_page_count: 0, ocr_page_count: 1,
          finished_at: Time.current)
      end

      get "/api/v1/leases/#{lease.id}/documents/#{version.contract_document_id}", headers: headers

      expect(json["data"]["versions"].first["text_extraction"])
        .to include("status" => "succeeded", "page_count" => 1, "ocr_page_count" => 1)
      expect(response.body).not_to include("Aluguel")
    end

    it "requests a new attempt after the previous one finished: 202, pending, job enqueued" do
      finish(latest_extraction(version))

      expect { reprocess }.to have_enqueued_job(ExtractDocumentTextJob).with(tenant_a.id, kind_of(String))

      expect(response).to have_http_status(:accepted)
      expect(json["data"]).to include("status" => "pending", "document_version_id" => version.id)
      expect(latest_extraction(version)).to have_attributes(id: json["data"]["id"], requested_by_id: user.id)
    end

    it "answers 409 while an attempt is pending" do
      expect { reprocess }.not_to have_enqueued_job(ExtractDocumentTextJob)

      expect(response).to have_http_status(:conflict)
      expect(json["error"]["code"]).to eq("extraction_in_progress")
    end

    %w[analyst viewer].each do |read_only_role|
      context "as #{read_only_role}" do
        let(:role) { read_only_role }

        it "is forbidden" do
          finish(latest_extraction(version))
          reprocess

          expect(response).to have_http_status(:forbidden)
          expect(with_tenant(tenant_a) { version.text_extractions.count }).to eq(1)
        end
      end
    end

    it "answers 404 for another tenant's version, exactly like a nonexistent one" do
      with_tenant(tenant_b) { create(:membership, tenant: tenant_b, user: create(:user), role: "owner") }
      version_b = upload_version(tenant_b, with_tenant(tenant_b) { create(:lease, tenant: tenant_b) })
      finish(latest_extraction(version_b, tenant: tenant_b), tenant: tenant_b)

      reprocess(version_b.id)
      expect(response).to have_http_status(:not_found)
      reprocess(SecureRandom.uuid)
      expect(response).to have_http_status(:not_found)
      expect(with_tenant(tenant_b) { version_b.text_extractions.count }).to eq(1)
    end

    it "answers 403 for the header of a tenant the user is not a member of" do
      reprocess(request_headers: { "X-Tenant-Id" => tenant_b.id })

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]["code"]).to eq("tenant_forbidden")
    end

    it "leaves no tenant context on the connection" do
      finish(latest_extraction(version))
      reprocess

      expect(current_db_setting("app.current_tenant_id")).to be_blank
    end

    it "does not issue more queries as the number of versions grows (no N+1)" do
      single = count_queries { get "/api/v1/leases/#{lease.id}/documents", headers: headers }
      2.times { upload_version(tenant_a, lease) }
      triple = count_queries { get "/api/v1/leases/#{lease.id}/documents", headers: headers }

      expect(triple).to eq(single)
    end
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].include?("set_config") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
