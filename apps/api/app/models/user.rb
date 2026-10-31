# Global identity (docs/domain/identity.md). Carries no tenant_id — a
# user's access to any tenant is expressed entirely through `memberships`.
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable, :trackable

  has_many :memberships, dependent: :restrict_with_error, inverse_of: :user
  has_many :tenants, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id,
    inverse_of: :invited_by

  validates :full_name, presence: true
end
