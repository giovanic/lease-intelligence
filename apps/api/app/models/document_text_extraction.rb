# One attempt at turning a DocumentVersion into per-page text
# (docs/adr/0016-document-text-extraction.md). Created `pending` by
# DocumentText::RequestExtraction, moved through `running` to `succeeded`
# or `failed` only by DocumentText::ProcessExtraction. Reprocessing is a new
# row; the "current" text of a version is its latest succeeded attempt.
# See db/migrate/20261031220000_create_document_text_extractions.rb for the
# RLS policy and the constraints these validations mirror.
class DocumentTextExtraction < ApplicationRecord
  # Why an attempt failed — a fixed vocabulary, never an exception message
  # (it could echo file content):
  # unreadable_file: the file could not be parsed or rasterized;
  # encrypted_pdf: password-protected PDF; too_many_pages: above MAX_PAGES;
  # timeout: a page took longer than the OCR limits; ocr_unavailable: the
  # OCR engine is not installed or failed to start; storage_unavailable:
  # the bytes could not be read; abandoned: stuck pending/running past
  # ABANDONED_AFTER (worker crash); internal_error: unexpected error after
  # the job's retries ran out.
  ERROR_CODES = %w[
    unreadable_file encrypted_pdf too_many_pages timeout ocr_unavailable storage_unavailable abandoned internal_error
  ].freeze
  MAX_PAGES = 300
  ABANDONED_AFTER = 1.hour

  belongs_to :tenant
  belongs_to :document_version
  belongs_to :requested_by, class_name: "User", optional: true
  has_many :pages, -> { order(:page_number) }, class_name: "DocumentTextPage", foreign_key: :text_extraction_id,
    inverse_of: :text_extraction

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

  validates :error_code, inclusion: { in: ERROR_CODES }, if: :failed?
  validates :error_code, absence: true, unless: :failed?

  scope :active, -> { where(status: %w[pending running]) }

  def active?
    pending? || running?
  end

  def finished?
    succeeded? || failed?
  end

  # Stuck pending/running for longer than any real run takes.
  def abandoned?(now = Time.current)
    active? && updated_at < now - ABANDONED_AFTER
  end
end
