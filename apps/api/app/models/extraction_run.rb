# One AI field extraction over a DocumentVersion
# (docs/adr/0017-contract-field-extraction-claude.md), reading one exact
# DocumentTextExtraction. Created `pending` by FieldExtraction::RequestRun,
# moved through `running` to `succeeded` or `failed` only by
# ExtractContractFieldsJob. Reprocessing is a new row; the version's
# "current" candidates are those of its latest succeeded run.
# See db/migrate/20261031230000_create_extraction_runs.rb for the RLS
# policy and the constraints these validations mirror.
class ExtractionRun < ApplicationRecord
  # Why a run failed — a fixed vocabulary, never a provider message (it
  # could echo contract content):
  # rate_limited: the provider kept answering 429 after the SDK's retries;
  # provider_unavailable: 5xx/529 or connection errors after the retries;
  # timeout: the request took longer than Llm::AnthropicProvider::TIMEOUT;
  # output_truncated: the answer hit max_tokens; refused: the model (and its
  # server-side fallback) declined; invalid_output: no JSON matching the
  # schema; text_too_long: the text read is above MAX_INPUT_CHARACTERS;
  # abandoned: stuck pending/running past ABANDONED_AFTER (worker crash);
  # internal_error: unexpected error after the job's retries ran out.
  ERROR_CODES = %w[
    rate_limited provider_unavailable timeout output_truncated refused invalid_output text_too_long abandoned
    internal_error
  ].freeze
  MAX_INPUT_CHARACTERS = 1_500_000
  ABANDONED_AFTER = 1.hour

  belongs_to :tenant
  belongs_to :document_version
  belongs_to :text_extraction, class_name: "DocumentTextExtraction"
  belongs_to :requested_by, class_name: "User", optional: true
  has_many :fields, -> { order(:position) }, class_name: "ExtractedField", inverse_of: :extraction_run

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

  validates :provider, :model, :prompt_version, :effort, presence: true
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
