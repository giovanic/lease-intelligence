module Portfolio
  # Edits a counterparty, including archiving it (status: "archived");
  # tenant ownership cannot change. Returns the Counterparty on success,
  # its ActiveModel::Errors on failure.
  class UpdateCounterparty
    def self.call(counterparty:, attributes:)
      if counterparty.update(attributes)
        ServiceResult.success(counterparty)
      else
        ServiceResult.failure(counterparty.errors)
      end
    end
  end
end
