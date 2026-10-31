# In-memory uploads for document specs. Each default payload is unique, so
# two uploads never collide on the per-tenant SHA-256 uniqueness rule
# unless a spec passes the same bytes on purpose.
module DocumentUploadHelpers
  PDF_HEADER = "%PDF-1.7\n%\xE2\xE3\xCF\xD3\n".b
  PNG_HEADER = "\x89PNG\r\n\x1A\n".b
  JPEG_HEADER = "\xFF\xD8\xFF\xE0".b
  TIFF_HEADER = "II*\x00".b

  def unique_pdf_bytes
    PDF_HEADER + "1 0 obj <<>> endobj #{SecureRandom.hex(16)}\n%%EOF\n".b
  end

  def uploaded_file(bytes = unique_pdf_bytes, filename: "contrato.pdf", content_type: "application/pdf")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, true, original_filename: filename)
  end
end

RSpec.configure do |config|
  config.include DocumentUploadHelpers

  # The test Disk service writes under tmp/storage; keep that directory
  # (and its tracked .keep) but drop what the suite stored.
  config.after(:suite) do
    root = ActiveStorage::Blob.service.root
    Dir.children(root).reject { |entry| entry == ".keep" }.each { |entry| FileUtils.rm_rf(File.join(root, entry)) }
  end
end
