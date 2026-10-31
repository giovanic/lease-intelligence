# Tenant-owned document slot of a lease (docs/domain/documents.md): "the
# original contract", "amendment #2". The files are its immutable
# DocumentVersions. See db/migrate/20261031200000_create_contract_documents.rb
# for the RLS policy and the constraints these validations mirror.
class ContractDocument < ApplicationRecord
  belongs_to :tenant
  belongs_to :lease
  has_many :versions, -> { order(version_number: :desc) }, class_name: "DocumentVersion",
    inverse_of: :contract_document

  # original_contract: the signed lease itself (at most one per lease);
  # amendment: an aditivo; other: any related document (guarantee letter,
  # inspection report, ...).
  enum :kind, { original_contract: "original_contract", amendment: "amendment", other: "other" }, validate: true

  normalizes :title, with: ->(value) { value.strip.presence }

  validates :title, presence: true, length: { maximum: 255 }
  validates :kind, uniqueness: { scope: :lease_id, message: "the lease already has an original contract" },
    if: :original_contract?

  def latest_version
    versions.first
  end
end
