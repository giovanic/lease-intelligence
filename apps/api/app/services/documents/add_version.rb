module Documents
  # Adds a new file version to an existing document — the only way to
  # "correct" a file, since versions are immutable (docs/adr/0010). The
  # document row is locked so concurrent uploads get distinct numbers.
  # Returns the new DocumentVersion on success, ActiveModel::Errors (under
  # `file`) on failure.
  class AddVersion
    def self.call(document:, uploaded_by:, file:)
      errors = ActiveModel::Errors.new(DocumentVersion.new)

      inspection = InspectUpload.call(file)
      file_error = inspection.failure? ? inspection.error : VersionWriter.duplicate_error(
        tenant_id: document.tenant_id, sha256: inspection.value.sha256
      )
      if file_error
        errors.add(:file, file_error)
        return ServiceResult.failure(errors)
      end

      version = ContractDocument.transaction(requires_new: true) do
        document.lock!
        VersionWriter.store!(document: document, upload: inspection.value, uploaded_by: uploaded_by)
      end
      ServiceResult.success(version)
    rescue ActiveRecord::RecordNotUnique => error
      raise unless VersionWriter.duplicate_violation?(error)

      errors.add(:file, "has already been uploaded")
      ServiceResult.failure(errors)
    end
  end
end
