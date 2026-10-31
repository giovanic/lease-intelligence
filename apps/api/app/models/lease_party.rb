# A counterparty's participation in a lease, with its role
# (docs/domain/leases.md). Tenant-owned; composite foreign keys keep the
# lease, the counterparty and the row itself in one tenant
# (db/migrate/20261031180001_create_lease_parties.rb).
class LeaseParty < ApplicationRecord
  belongs_to :tenant
  belongs_to :lease
  belongs_to :counterparty

  # lessor: locador (at least one per lease, enforced by the Leases
  # services); guarantor: fiador; intervening_party: interveniente anuente.
  enum :role, { lessor: "lessor", guarantor: "guarantor", intervening_party: "intervening_party" }, validate: true

  validates :counterparty_id, uniqueness: { scope: :lease_id }
end
