module Documents
  # The write rules shared by CreateDocument and AddVersion — use those, not
  # this class directly.
  #
  # - `duplicate_error`: the same bytes may be stored once per tenant
  #   (docs/adr/0015); the unique (tenant_id, sha256) index is the backstop
  #   for a concurrent upload, see `duplicate_violation?`.
  # - `store!`: inside the caller's transaction, numbers the version, inserts
  #   the row and only then writes the bytes, so a storage failure rolls the
  #   row back. The caller must hold a lock on (or have just inserted) the
  #   document, so two uploads cannot take the same number.
  class VersionWriter
    DUPLICATE_INDEX = "idx_document_versions_unique_sha256_per_tenant".freeze

    def self.duplicate_error(tenant_id:, sha256:)
      existing = DocumentVersion.where(tenant_id: tenant_id).includes(:contract_document).find_by(sha256: sha256)
      return unless existing

      %(has already been uploaded as "#{existing.contract_document.title}" (version #{existing.version_number}))
    end

    def self.duplicate_violation?(error)
      error.message.include?(DUPLICATE_INDEX)
    end

    def self.store!(document:, upload:, uploaded_by:)
      version_id = SecureRandom.uuid
      storage_key = FileStore.key_for(tenant_id: document.tenant_id, version_id: version_id)
      next_number = DocumentVersion.where(contract_document_id: document.id).maximum(:version_number).to_i + 1

      version = DocumentVersion.create!(
        id: version_id, tenant: document.tenant, contract_document: document, version_number: next_number,
        storage_key: storage_key, original_filename: upload.original_filename, content_type: upload.content_type,
        byte_size: upload.byte_size, sha256: upload.sha256, uploaded_by: uploaded_by
      )
      FileStore.upload(storage_key, upload.io, md5_base64: upload.md5_base64, content_type: upload.content_type)
      version
    end
  end
end
