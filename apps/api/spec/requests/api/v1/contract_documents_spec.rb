require "rails_helper"

# Request layer of the three-layer tenant isolation test, plus the endpoint
# contracts documented in Api::V1::ContractDocumentsController and
# Api::V1::DocumentVersionsController.
RSpec.describe "/api/v1/leases/:lease_id/documents", type: :request do
  let(:user) { create(:user, full_name: "Ana Gestora") }
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:role) { "manager" }
  let!(:membership) { with_tenant(tenant_a) { create(:membership, tenant: tenant_a, user: user, role: role) } }
  let(:headers) { { "X-Tenant-Id" => tenant_a.id } }
  let!(:lease) { with_tenant(tenant_a) { create(:lease, tenant: tenant_a) } }
  let!(:lease_b) { with_tenant(tenant_b) { create(:lease, tenant: tenant_b) } }
  let(:documents_path) { "/api/v1/leases/#{lease.id}/documents" }

  def upload_document(lease_id: lease.id, file: uploaded_file, kind: "original_contract", title: "Contrato assinado",
    request_headers: headers)
    post "/api/v1/leases/#{lease_id}/documents", params: { document: { kind: kind, title: title, file: file } },
      headers: request_headers
  end

  def create_document(tenant, lease, **attributes)
    with_tenant(tenant, user: user) do
      Documents::CreateDocument.call(lease: lease, uploaded_by: user,
        attributes: { kind: "amendment", title: "Aditivo" }.merge(attributes), file: uploaded_file).value
    end
  end

  it "returns 401 when not signed in" do
    get documents_path, headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  context "when signed in" do
    before { sign_in_as(user) }

    describe "GET index" do
      it "lists the lease's documents with their versions, paginated" do
        document = create_document(tenant_a, lease, title: "Aditivo 1")
        create_document(tenant_a, with_tenant(tenant_a) { create(:lease, tenant: tenant_a) }, title: "Outro contrato")

        get documents_path, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"].pluck("id")).to eq([ document.id ])
        expect(json["data"].first["versions"].first).to include(
          "version_number" => 1, "content_type" => "application/pdf", "original_filename" => "contrato.pdf",
          "uploaded_by" => { "id" => user.id, "full_name" => "Ana Gestora" }
        )
        expect(json["data"].first["versions"].first.keys).not_to include("storage_key")
        expect(json["meta"]).to eq("page" => 1, "per_page" => 25, "total_count" => 1, "total_pages" => 1)
      end

      it "answers 404 for a lease of another tenant" do
        create_document(tenant_b, lease_b, title: "Belongs to B")

        get "/api/v1/leases/#{lease_b.id}/documents", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("Belongs to B")
      end

      it "requires the tenant header" do
        get documents_path

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("tenant_required")
      end
    end

    describe "GET show" do
      it "returns the document" do
        document = create_document(tenant_a, lease)

        get "#{documents_path}/#{document.id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(json["data"]).to include("id" => document.id, "lease_id" => lease.id, "kind" => "amendment")
      end

      it "answers 404 for another tenant's document, or one of another lease" do
        other_tenant_document = create_document(tenant_b, lease_b)
        other_lease_document = create_document(tenant_a, with_tenant(tenant_a) { create(:lease, tenant: tenant_a) })

        get "#{documents_path}/#{other_tenant_document.id}", headers: headers
        expect(response).to have_http_status(:not_found)

        get "#{documents_path}/#{other_lease_document.id}", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST create (multipart)" do
      it "creates the document with version 1" do
        upload_document(file: uploaded_file(filename: "Contrato Loja 12.pdf"))

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("kind" => "original_contract", "title" => "Contrato assinado", "lease_id" => lease.id)
        expect(json["data"]["versions"].sole).to include("version_number" => 1, "original_filename" => "Contrato Loja 12.pdf")
        expect(with_tenant(tenant_a) { DocumentVersion.sole.tenant_id }).to eq(tenant_a.id)
      end

      it "answers 422 with field details for an invalid file or a duplicate" do
        bytes = unique_pdf_bytes
        upload_document(file: uploaded_file("<html>".b, filename: "fake.pdf"))

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "details", "file")).to eq([ "must be a PDF, JPEG, PNG or TIFF file" ])

        upload_document(file: uploaded_file(bytes))
        upload_document(kind: "amendment", file: uploaded_file(bytes))
        expect(json.dig("error", "details", "file")).to eq([ %(has already been uploaded as "Contrato assinado" (version 1)) ])
      end

      %w[analyst viewer].each do |read_only_role|
        context "as #{read_only_role}" do
          let(:role) { read_only_role }

          it "answers 403 and stores nothing" do
            upload_document

            expect(response).to have_http_status(:forbidden)
            expect(with_tenant(tenant_a) { ContractDocument.count }).to eq(0)
          end
        end
      end

      it "answers 404 for a lease of another tenant and stores nothing" do
        upload_document(lease_id: lease_b.id)

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { ContractDocument.count }).to eq(0)
      end

      it "refuses a multipart body without the tenant header (CSRF guard)" do
        upload_document(request_headers: {})

        expect(response).to have_http_status(:bad_request)
        expect(json.dig("error", "code")).to eq("tenant_required")
      end

      it "refuses a cross-site multipart request" do
        upload_document(request_headers: headers.merge("Origin" => "https://evil.example"))

        expect(response).to have_http_status(:forbidden)
        expect(json.dig("error", "code")).to eq("cross_site_request")
      end

      it "keeps refusing multipart bodies on endpoints that did not opt in" do
        post "/api/v1/leases", params: { lease: { title: "x", file: uploaded_file } }, headers: headers

        expect(response).to have_http_status(:unsupported_media_type)
      end

      it "answers 503 and stores nothing when the storage backend fails" do
        allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)

        upload_document

        expect(response).to have_http_status(:service_unavailable)
        expect(json.dig("error", "code")).to eq("storage_unavailable")
        expect(with_tenant(tenant_a) { ContractDocument.count }).to eq(0)
      end
    end

    describe "POST versions (multipart)" do
      let!(:document) { create_document(tenant_a, lease) }
      let(:versions_path) { "#{documents_path}/#{document.id}/versions" }

      it "adds version 2" do
        post versions_path, params: { version: { file: uploaded_file(DocumentUploadHelpers::JPEG_HEADER + "scan".b) } },
          headers: headers

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("version_number" => 2, "content_type" => "image/jpeg",
          "contract_document_id" => document.id)
      end

      it "answers 400 without a file part" do
        post versions_path, params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 404 for a document of another tenant" do
        other = create_document(tenant_b, lease_b)

        post "/api/v1/leases/#{lease_b.id}/documents/#{other.id}/versions", params: { version: { file: uploaded_file } },
          headers: headers

        expect(response).to have_http_status(:not_found)
        expect(with_tenant(tenant_b) { DocumentVersion.count }).to eq(1)
      end

      context "as viewer" do
        let(:role) { "viewer" }

        it "answers 403" do
          post versions_path, params: { version: { file: uploaded_file } }, headers: headers

          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
