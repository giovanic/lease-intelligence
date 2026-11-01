# One candidate value of an ExtractionRun
# (docs/adr/0017-contract-field-extraction-claude.md, docs/adr/0011): what
# the AI read, with at least one EvidenceReference into the text. Not a
# contractual fact — nothing downstream may read it as one; only a future
# ReviewDecision approves it. `field_key` and the value's shape come from
# FieldExtraction::Catalog. Written once, by FieldExtraction::RecordOutcome;
# the database rejects any UPDATE or DELETE
# (db/migrate/20261031230001_create_extracted_fields.rb), and `readonly?`
# makes ActiveRecord refuse before even trying.
class ExtractedField < ApplicationRecord
  belongs_to :tenant
  belongs_to :extraction_run, inverse_of: :fields
  has_many :evidence_references, -> { order(:page_number, :start_offset) }, inverse_of: :extracted_field
  # Human decisions, oldest first; the latest is the field's current state (docs/adr/0019).
  has_many :review_decisions, -> { order(:created_at, :id) }, inverse_of: :extracted_field

  # Which value column is set: date -> value_date; integer -> value_integer;
  # money -> value_amount + value_currency; option -> value_text (an option
  # code of the catalog); text -> value_text; party -> value_text (name) +
  # optional value_tax_id (CPF/CNPJ digits).
  enum :value_type, { date: "date", integer: "integer", money: "money", option: "option", text: "text",
    party: "party" }, prefix: :value, validate: true

  validates :field_key, format: { with: /\A[a-z][a-z_]*\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def readonly?
    persisted? || super
  end
end
