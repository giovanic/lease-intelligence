module Leases
  # Edits a lease: its own attributes, its property (only while a draft)
  # and, when `parties` is given, replaces its parties. Tenant ownership
  # cannot change. Returns the Lease on success, its ActiveModel::Errors on
  # failure.
  class UpdateLease
    def self.call(lease:, attributes:)
      LeaseWriter.call(lease, attributes)
    end
  end
end
