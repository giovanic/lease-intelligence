module Documents
  # Registers a document of a lease together with its first file (version
  # 1). The tenant is the lease's — the caller found the lease under RLS
  # through the server-resolved membership. `attributes`: kind, title.
  # Returns the ContractDocument on success, its ActiveModel::Errors on
  # failure (file problems under `file`).
  class CreateDocument
    ORIGINAL_INDEX = "idx_contract_documents_one_original_per_lease".freeze

    def self.call(lease:, uploaded_by:, attributes:, file:)
      document = ContractDocument.new(tenant: lease.tenant, lease: lease)
      document.assign_attributes(attributes.to_h.with_indifferent_access.slice(:kind, :title))

      inspection = InspectUpload.call(file)
      document.validate
      file_error = inspection.failure? ? inspection.error : VersionWriter.duplicate_error(
        tenant_id: document.tenant_id, sha256: inspection.value.sha256
      )
      document.errors.add(:file, file_error) if file_error
      return ServiceResult.failure(document.errors) if document.errors.any?

      ContractDocument.transaction(requires_new: true) do
        document.save!
        VersionWriter.store!(document: document, upload: inspection.value, uploaded_by: uploaded_by)
      end
      document.versions.reload # loaded inside the caller's tenant context
      ServiceResult.success(document)
    rescue ActiveRecord::RecordNotUnique => error
      # A concurrent upload won the race between the checks above and the insert.
      if VersionWriter.duplicate_violation?(error)
        document.errors.add(:file, "has already been uploaded")
      elsif error.message.include?(ORIGINAL_INDEX)
        document.errors.add(:kind, "the lease already has an original contract")
      else
        raise
      end
      ServiceResult.failure(document.errors)
    end
  end
end
