# Tenant-owned (docs/domain/identity.md). Targets an email, not
# necessarily an existing User. `token` is the unguessable capability
# used by the (not-yet-built) accept-invitation endpoint — see
# db/migrate/20261031133226_create_invitations.rb and
# docs/adr/0003-postgresql-rls.md for the open question on how that
# lookup will work under RLS with no tenant context yet established.
class Invitation < ApplicationRecord
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  belongs_to :tenant, inverse_of: :invitations
  belongs_to :invited_by, class_name: "User", inverse_of: :sent_invitations
  has_one :membership, dependent: :nullify, inverse_of: :invitation

  enum :role, { owner: "owner", admin: "admin", manager: "manager", analyst: "analyst", viewer: "viewer" }
  enum :status, { pending: "pending", accepted: "accepted", revoked: "revoked", expired: "expired" },
    default: "pending"

  has_secure_token :token

  before_validation { self.email = email.to_s.downcase }

  validates :email, presence: true, format: { with: EMAIL_FORMAT }
  validates :expires_at, presence: true
  validates :email, uniqueness: {
    scope: :tenant_id,
    conditions: -> { where(status: "pending") },
    message: "already has a pending invitation for this organization"
  }

  scope :pending, -> { where(status: "pending") }

  def expired?
    expires_at.past?
  end
end
