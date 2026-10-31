module Portfolio
  # Edits a property, including archiving it (status: "archived"); tenant
  # ownership cannot change. Returns the Property on success, its
  # ActiveModel::Errors on failure.
  class UpdateProperty
    def self.call(property:, attributes:)
      property.update(attributes) ? ServiceResult.success(property) : ServiceResult.failure(property.errors)
    end
  end
end
