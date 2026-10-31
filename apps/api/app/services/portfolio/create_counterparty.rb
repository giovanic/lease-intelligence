module Portfolio
  # Registers a counterparty (landlord/lessor) for the given tenant — the
  # tenant comes from the caller's server-resolved membership, never from
  # request input. Returns the Counterparty on success, its
  # ActiveModel::Errors on failure.
  class CreateCounterparty
    def self.call(tenant:, attributes:)
      counterparty = Counterparty.new(attributes)
      counterparty.tenant = tenant

      counterparty.save ? ServiceResult.success(counterparty) : ServiceResult.failure(counterparty.errors)
    end
  end
end
