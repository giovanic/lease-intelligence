# Root tenancy anchor (docs/domain/identity.md). Deliberately has no RLS —
# see db/migrate/20261031133222_create_tenants.rb for why. No code path
# should ever do `Tenant.all` as a way to browse organizations; always go
# through the current user's `memberships`.
class Tenant < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  has_many :memberships, dependent: :restrict_with_error, inverse_of: :tenant
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy, inverse_of: :tenant
  # Who last turned AI field extraction on or off (docs/adr/0018).
  belongs_to :ai_extraction_changed_by, class_name: "User", optional: true

  enum :status, { active: "active", suspended: "suspended", canceled: "canceled" }, default: "active"

  before_validation { self.slug = slug.to_s.downcase }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }
end
