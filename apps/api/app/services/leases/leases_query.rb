module Leases
  # Filters and orders an already tenant-scoped Lease relation for
  # GET /api/v1/leases. `search` matches title or code (case-insensitive
  # substring; LIKE wildcards escaped). Preloads what LeaseSerializer reads.
  class LeasesQuery
    def self.call(relation, status: nil, property_id: nil, counterparty_id: nil, search: nil)
      relation = relation.where(status: status) if status
      relation = relation.where(property_id: property_id) if property_id
      if counterparty_id
        relation = relation.where(id: LeaseParty.where(counterparty_id: counterparty_id).select(:lease_id))
      end
      if search.present?
        term = "%#{Lease.sanitize_sql_like(search.strip)}%"
        relation = relation.where("leases.title ILIKE :term OR leases.code ILIKE :term", term: term)
      end
      relation.includes(:property, lease_parties: :counterparty).order(:title, :id)
    end
  end
end
