require "rails_helper"

RSpec.describe "Documents services" do
  let(:tenant) { create(:tenant) }
  let(:user) { create(:user, full_name: "Ana Gestora") }
  let!(:lease) { with_tenant(tenant) { create(:lease, tenant: tenant) } }
  let(:store) { ActiveStorage::Blob.service }

  describe Documents::InspectUpload do
    {
      "application/pdf" => DocumentUploadHelpers::PDF_HEADER,
      "image/png" => DocumentUploadHelpers::PNG_HEADER,
      "image/jpeg" => DocumentUploadHelpers::JPEG_HEADER,
      "image/tiff" => DocumentUploadHelpers::TIFF_HEADER,
      "image/tiff (big-endian)" => "MM\x00*".b
    }.each do |label, header|
      it "detects #{label} from the leading bytes, ignoring name and declared type" do
        result = described_class.call(uploaded_file(header + "rest".b, filename: "scan.bin", content_type: "text/plain"))

        expect(result).to be_success
        expect(result.value.content_type).to eq(label.split.first)
      end
    end

    it "rejects a file that only claims to be a PDF" do
      result = described_class.call(uploaded_file("<html><script>x</script>".b, filename: "contrato.pdf"))

      expect(result.error).to eq("must be a PDF, JPEG, PNG or TIFF file")
    end

    it "rejects a missing, empty or too large file" do
      expect(described_class.call(nil).error).to eq("can't be blank")
      expect(described_class.call("not a file").error).to eq("can't be blank")
      expect(described_class.call(uploaded_file("".b)).error).to eq("is empty")

      too_large = uploaded_file(DocumentUploadHelpers::PDF_HEADER)
      allow(too_large).to receive(:size).and_return(50.megabytes + 1)
      expect(described_class.call(too_large).error).to eq("is too large (maximum is 50 MB)")
    end

    it "computes SHA-256, MD5 and size of the whole content" do
      bytes = DocumentUploadHelpers::PDF_HEADER + ("x" * 3.megabytes).b
      result = described_class.call(uploaded_file(bytes))

      expect(result.value.sha256).to eq(Digest::SHA256.hexdigest(bytes))
      expect(result.value.md5_base64).to eq(Digest::MD5.base64digest(bytes))
      expect(result.value.byte_size).to eq(bytes.bytesize)
    end

    it "keeps only a clean base name of the original filename" do
      name = ->(original) { described_class.call(uploaded_file(filename: original)).value.original_filename }

      expect(name.call("C:\\Users\\ana\\Contrato Loja 12.pdf")).to eq("Contrato Loja 12.pdf")
      expect(name.call("../../etc/passwd")).to eq("passwd")
      expect(name.call("a\u0000b\nc.pdf")).to eq("abc.pdf")
      expect(name.call("..")).to eq("document")
      expect(name.call("#{'a' * 300}.pdf").length).to eq(255)
    end
  end

  describe Documents::CreateDocument do
    def create_document(file: uploaded_file, **attributes)
      with_tenant(tenant, user: user) do
        described_class.call(lease: lease, uploaded_by: user, attributes: { kind: "original_contract", title: "Contrato" }
          .merge(attributes), file: file)
      end
    end

    it "creates the document with version 1 and stores the exact bytes under the tenant prefix" do
      bytes = unique_pdf_bytes
      result = create_document(file: uploaded_file(bytes, filename: "Contrato Loja.pdf"))

      expect(result).to be_success
      document = result.value
      version = document.versions.sole
      expect(version).to have_attributes(
        version_number: 1, tenant_id: tenant.id, original_filename: "Contrato Loja.pdf", content_type: "application/pdf",
        byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), uploaded_by_id: user.id,
        storage_key: "tenants/#{tenant.id}/document_versions/#{version.id}"
      )
      expect(store.download(version.storage_key)).to eq(bytes)
    end

    it "reports document and file errors together without storing anything" do
      result = create_document(kind: "invoice", title: "", file: uploaded_file("plain text".b))

      expect(result).to be_failure
      expect(result.error.to_hash).to include(kind: [ "is not included in the list" ], title: [ "can't be blank" ],
        file: [ "must be a PDF, JPEG, PNG or TIFF file" ])
      expect(with_tenant(tenant) { [ ContractDocument.count, DocumentVersion.count ] }).to eq([ 0, 0 ])
    end

    it "rejects bytes already uploaded in the tenant, naming where they are" do
      bytes = unique_pdf_bytes
      create_document(file: uploaded_file(bytes), title: "Contrato assinado")

      result = create_document(kind: "amendment", title: "Cópia", file: uploaded_file(bytes))

      expect(result.error[:file]).to eq([ %(has already been uploaded as "Contrato assinado" (version 1)) ])
    end

    it "turns a lost duplicate race (unique index) into a validation error" do
      allow(Documents::VersionWriter).to receive(:duplicate_error).and_return(nil)
      bytes = unique_pdf_bytes
      create_document(file: uploaded_file(bytes))

      result = create_document(kind: "amendment", file: uploaded_file(bytes))

      expect(result.error[:file]).to eq([ "has already been uploaded" ])
      expect(with_tenant(tenant) { ContractDocument.count }).to eq(1)
    end

    it "rejects a second original contract for the same lease" do
      create_document

      result = create_document

      expect(result.error[:kind]).to eq([ "the lease already has an original contract" ])
    end

    it "rolls the rows back and raises when storage fails" do
      allow(store).to receive(:upload).and_raise(Errno::ENOSPC)

      expect { create_document }.to raise_error(Documents::FileStore::Error, /storage upload failed \(Errno::ENOSPC\)/)
      expect(with_tenant(tenant) { [ ContractDocument.count, DocumentVersion.count ] }).to eq([ 0, 0 ])
    end
  end

  describe Documents::AddVersion do
    let!(:document) do
      with_tenant(tenant, user: user) do
        Documents::CreateDocument.call(lease: lease, uploaded_by: user, attributes: { kind: "amendment", title: "Aditivo 1" },
          file: uploaded_file).value
      end
    end

    def add_version(file = uploaded_file)
      with_tenant(tenant, user: user) { described_class.call(document: document, uploaded_by: user, file: file) }
    end

    it "numbers new versions after the latest and keeps the earlier ones untouched" do
      first = with_tenant(tenant) { document.versions.sole }

      second = add_version(uploaded_file(DocumentUploadHelpers::PNG_HEADER + "scan".b, filename: "aditivo.png")).value
      third = add_version.value

      expect([ second.version_number, third.version_number ]).to eq([ 2, 3 ])
      expect(second.content_type).to eq("image/png")
      expect(with_tenant(tenant) { DocumentVersion.find(first.id) }).to have_attributes(first.attributes.except("tenant"))
      expect(store.exist?(first.storage_key)).to be(true)
    end

    it "rejects an invalid or already uploaded file" do
      existing = with_tenant(tenant) { document.versions.sole }
      same_bytes = store.download(existing.storage_key)

      expect(add_version(uploaded_file("nope".b)).error[:file]).to eq([ "must be a PDF, JPEG, PNG or TIFF file" ])
      expect(add_version(uploaded_file(same_bytes)).error[:file])
        .to eq([ %(has already been uploaded as "Aditivo 1" (version 1)) ])
      expect(with_tenant(tenant) { DocumentVersion.count }).to eq(1)
    end
  end

  describe Documents::DownloadLink do
    let(:version) { build_stubbed(:document_version, tenant: tenant) }

    it "round-trips version, tenant and user, and expires after 5 minutes" do
      link = described_class.issue(version: version, user: user)

      expect(link.expires_at).to be_within(1.second).of(5.minutes.from_now)
      expect(described_class.resolve(link.token))
        .to eq("version_id" => version.id, "tenant_id" => tenant.id, "user_id" => user.id)
      expect(link.token).to match(/\A[A-Za-z0-9_=-]+\z/) # URL-safe: usable as a path segment

      travel 5.minutes + 1.second do
        expect(described_class.resolve(link.token)).to be_nil
      end
    end

    it "rejects tampered, malformed and foreign tokens" do
      token = described_class.issue(version: version, user: user).token
      foreign = ActiveSupport::MessageVerifier.new("other secret", url_safe: true)
        .generate({ "version_id" => version.id, "tenant_id" => tenant.id, "user_id" => user.id })

      expect(described_class.resolve(token.sub(/.\z/) { |char| char == "A" ? "B" : "A" })).to be_nil
      expect(described_class.resolve("garbage")).to be_nil
      expect(described_class.resolve("")).to be_nil
      expect(described_class.resolve(nil)).to be_nil
      expect(described_class.resolve(foreign)).to be_nil
    end
  end
end
