# Explicit JSON shape for a Lease, with summaries of its property and of
# each party's counterparty. The counterparty summary leaves out tax_id,
# email and phone (personal data under LGPD) — the full record is at
# GET /api/v1/counterparties/:id.
class LeaseSerializer
  def initialize(lease)
    @lease = lease
  end

  def as_json(*)
    {
      id: @lease.id,
      title: @lease.title,
      code: @lease.code,
      status: @lease.status,
      notes: @lease.notes,
      property: property_summary(@lease.property),
      parties: @lease.lease_parties.map { |party| party_summary(party) },
      created_at: @lease.created_at,
      updated_at: @lease.updated_at
    }
  end

  private

  def property_summary(property)
    { id: property.id, name: property.name, code: property.code, city: property.city, state: property.state }
  end

  def party_summary(party)
    counterparty = party.counterparty
    {
      id: party.id,
      role: party.role,
      counterparty: {
        id: counterparty.id,
        kind: counterparty.kind,
        legal_name: counterparty.legal_name,
        trade_name: counterparty.trade_name
      }
    }
  end
end
