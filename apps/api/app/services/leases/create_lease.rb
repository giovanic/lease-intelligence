module Leases
  # Registers a lease, with its property and parties, for the given tenant
  # — the tenant comes from the caller's server-resolved membership, never
  # from request input. `attributes`: title, code, notes, status,
  # property_id, parties: [{ counterparty_id, role }] (see LeaseWriter for
  # the rules). Returns the Lease on success, its ActiveModel::Errors on
  # failure.
  class CreateLease
    def self.call(tenant:, attributes:)
      lease = Lease.new
      lease.tenant = tenant

      LeaseWriter.call(lease, attributes)
    end
  end
end
