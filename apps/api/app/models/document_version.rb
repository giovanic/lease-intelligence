# One immutable file of a ContractDocument (docs/domain/documents.md,
# docs/adr/0010, docs/adr/0015). The bytes live in the storage service
# under `storage_key`; this row is the only reference to them, behind RLS.
# Created only by Documents::VersionWriter; the database rejects any UPDATE
# or DELETE (db/migrate/20261031200001_create_document_versions.rb), and
# `readonly?` makes ActiveRecord refuse before even trying.
class DocumentVersion < ApplicationRecord
  CONTENT_TYPES = %w[application/pdf image/jpeg image/png image/tiff].freeze
  MAX_BYTE_SIZE = 50.megabytes

  belongs_to :tenant
  belongs_to :contract_document
  belongs_to :uploaded_by, class_name: "User"
  has_many :text_extractions, -> { order(:created_at, :id) }, class_name: "DocumentTextExtraction",
    inverse_of: :document_version
  # The attempt the API reports (docs/adr/0016); preloadable for lists.
  has_one :latest_text_extraction, -> { order(created_at: :desc, id: :desc) }, class_name: "DocumentTextExtraction"
  has_many :extraction_runs, -> { order(:created_at, :id) }, inverse_of: :document_version
  # The AI field extraction run the API reports (docs/adr/0017); preloadable for lists.
  has_one :latest_extraction_run, -> { order(created_at: :desc, id: :desc) }, class_name: "ExtractionRun"

  validates :version_number, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :storage_key, :original_filename, :sha256, presence: true
  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :byte_size, numericality: { only_integer: true, in: 1..MAX_BYTE_SIZE }

  def readonly?
    persisted? || super
  end
end
