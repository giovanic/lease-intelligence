# Tenant-owned registration record of a commercial lease
# (docs/domain/leases.md): property, internal title/code, lifecycle status
# and the counterparties involved (lease_parties). See
# db/migrate/20261031180000_create_leases.rb for the RLS policy and the
# database constraints these validations mirror.
#
# Contractual terms (dates, rent, indexation) are not attributes of the
# lease: they will be effective-dated ContractualConditions (docs/adr/0010).
class Lease < ApplicationRecord
  belongs_to :tenant
  belongs_to :property
  has_many :lease_parties, -> { order(:created_at, :id) }, inverse_of: :lease
  has_many :counterparties, through: :lease_parties

  # draft: being registered, not yet in force; active: in force;
  # expired: its term ended; terminated: ended early (rescission/distrato).
  # Transitions are not a state machine yet (docs/domain/leases.md).
  enum :status, { draft: "draft", active: "active", expired: "expired", terminated: "terminated" },
    default: "draft", validate: true

  normalizes :title, :notes, with: ->(value) { value.strip.presence }
  normalizes :code, with: ->(value) { value.strip.upcase.presence }

  validates :title, presence: true, length: { maximum: 255 }
  validates :code, length: { maximum: 50 }, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates :notes, length: { maximum: 5000 }
end
