# Tenant-owned join of User <-> Tenant, carrying the role Pundit policies
# will authorize against (docs/domain/identity.md). See
# db/migrate/20261031133227_create_memberships.rb for the RLS design,
# including the self-visibility policy that lets a user list their own
# memberships across tenants.
class Membership < ApplicationRecord
  belongs_to :tenant, inverse_of: :memberships
  belongs_to :user, inverse_of: :memberships
  belongs_to :invitation, inverse_of: :membership, optional: true

  enum :role, { owner: "owner", admin: "admin", manager: "manager", analyst: "analyst", viewer: "viewer" }
  enum :status, { active: "active", suspended: "suspended" }, default: "active"

  validates :user_id, uniqueness: { scope: :tenant_id }
  validate :invitation_belongs_to_same_tenant

  scope :active_memberships, -> { where(status: "active") }

  private

  # Mirrors the database-enforced composite foreign key
  # (memberships_invitation_same_tenant) with a clearer error message at
  # the Rails level; the database constraint remains the real guarantee.
  def invitation_belongs_to_same_tenant
    return if invitation.nil?
    return if invitation.tenant_id == tenant_id

    errors.add(:invitation, "must belong to the same tenant as this membership")
  end
end
