# Inserts go through RLS — call these inside `with_tenant(tenant) { ... }`.
#
# :document_version writes the row directly, without bytes in storage
# (versions are normally created by Documents::VersionWriter); use the
# services when a spec needs the file itself.
FactoryBot.define do
  factory :contract_document do
    tenant
    lease { association :lease, tenant: tenant }
    kind { "amendment" }
    sequence(:title) { |n| "Aditivo #{n}" }
  end

  factory :document_version do
    contract_document
    tenant { contract_document.tenant }
    uploaded_by factory: :user
    sequence(:version_number)
    storage_key { "tenants/#{tenant.id}/document_versions/#{SecureRandom.uuid}" }
    original_filename { "contrato.pdf" }
    content_type { "application/pdf" }
    byte_size { 1024 }
    sha256 { SecureRandom.hex(32) }
  end

  # A pending attempt, written directly (normally DocumentText::RequestExtraction).
  factory :document_text_extraction do
    document_version
    tenant { document_version.tenant }
    status { "pending" }
  end

  factory :document_text_page do
    text_extraction factory: :document_text_extraction
    tenant { text_extraction.tenant }
    sequence(:page_number)
    source { "native" }
    text { "Cláusula primeira" }
  end
end
