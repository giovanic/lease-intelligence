module Leases
  # The write rules shared by CreateLease and UpdateLease — use those, not
  # this class. Validates and saves a lease together with its parties in
  # one transaction:
  #
  # - property_id and every counterparty_id are looked up within the
  #   lease's tenant (and under RLS), so another tenant's id is "not found";
  #   the composite foreign keys are the database backstop.
  # - an archived property/counterparty cannot be newly linked (one that is
  #   already linked stays).
  # - the property can only change while the lease is a draft.
  # - parties: each counterparty once, at least one lessor. When given, the
  #   list replaces the lease's parties; when omitted on update, they stay.
  #
  # Errors on parties are keyed by position, e.g.
  # "parties[1].counterparty_id" => ["not found"].
  class LeaseWriter
    LEASE_ATTRIBUTES = %i[title code notes status].freeze

    def self.call(lease, attributes)
      new(lease, attributes).call
    end

    def initialize(lease, attributes)
      @lease = lease
      @attributes = attributes.to_h.with_indifferent_access
      @errors = []
    end

    def call
      @lease.assign_attributes(@attributes.slice(*LEASE_ATTRIBUTES))
      resolve_property if @lease.new_record? || @attributes.key?(:property_id)
      parties = resolve_parties if @lease.new_record? || @attributes.key?(:parties)

      @lease.validate
      # Reported as property_id below; belongs_to's "must exist" would repeat it.
      @lease.errors.delete(:property) if @errors.any? { |attribute, _| attribute == :property_id }
      @errors.each { |attribute, message| @lease.errors.add(attribute, message) }
      return ServiceResult.failure(@lease.errors) if @lease.errors.any?

      Lease.transaction do
        @lease.save!
        replace_parties(parties) if parties
      end
      ServiceResult.success(@lease)
    end

    private

    def resolve_property
      property_id = @attributes[:property_id]
      return add_error(:property_id, "can't be blank") if property_id.blank?

      property = Property.where(tenant_id: @lease.tenant_id).find_by(id: property_id)
      return add_error(:property_id, "not found") unless property
      return if property.id == @lease.property_id

      if @lease.persisted? && @lease.status_in_database != "draft"
        return add_error(:property_id, "can only change while the lease is a draft")
      end
      return add_error(:property_id, "is archived") if property.archived?

      @lease.property = property
    end

    # Returns [[counterparty, role], ...] (only meaningful when no error was added).
    def resolve_parties
      entries = @attributes[:parties] || []
      requested_ids = entries.map { |entry| entry[:counterparty_id].to_s.downcase }
      found = Counterparty.where(tenant_id: @lease.tenant_id, id: requested_ids).index_by(&:id)
      linked_ids = @lease.lease_parties.map(&:counterparty_id)

      parties = entries.each_with_index.filter_map do |entry, index|
        counterparty = found[requested_ids[index]]
        role = entry[:role].to_s

        if counterparty.nil?
          add_error(:"parties[#{index}].counterparty_id", "not found")
        elsif counterparty.archived? && linked_ids.exclude?(counterparty.id)
          add_error(:"parties[#{index}].counterparty_id", "is archived")
        elsif !LeaseParty.roles.key?(role)
          add_error(:"parties[#{index}].role", "is not included in the list")
        else
          [ counterparty, role ]
        end
      end

      add_error(:parties, "must not repeat a counterparty") if requested_ids.uniq.size < requested_ids.size
      add_error(:parties, "must include at least one lessor") if entries.none? { |entry| entry[:role].to_s == "lessor" }
      parties
    end

    def replace_parties(parties)
      existing = @lease.lease_parties.index_by(&:counterparty_id)
      wanted = parties.to_h { |counterparty, role| [ counterparty.id, [ counterparty, role ] ] }

      existing.each { |counterparty_id, party| party.destroy! unless wanted.key?(counterparty_id) }
      wanted.each do |counterparty_id, (counterparty, role)|
        party = existing[counterparty_id] ||
          LeaseParty.new(tenant: @lease.tenant, lease: @lease, counterparty: counterparty)
        party.update!(role: role)
      end
      # Loaded now, inside the tenant context, rather than lazily later.
      @lease.lease_parties.reload
    end

    def add_error(attribute, message)
      @errors << [ attribute, message ]
      nil
    end
  end
end
