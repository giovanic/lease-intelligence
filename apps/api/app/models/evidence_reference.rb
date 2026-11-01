# Where an ExtractedField was read (docs/adr/0011,
# docs/adr/0017-contract-field-extraction-claude.md): a page of the text
# the run read and the character span [start_offset, end_offset) of the
# quote in that page's stored text, checked by FieldExtraction::ValidateOutput
# before it is written. The snippet is not stored — `snippet` slices it
# from the page. Append-only, like ExtractedField.
class EvidenceReference < ApplicationRecord
  belongs_to :tenant
  belongs_to :extracted_field, inverse_of: :evidence_references
  belongs_to :text_page, class_name: "DocumentTextPage"

  validates :page_number, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :start_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :end_offset, numericality: { only_integer: true, greater_than: :start_offset }

  # The quoted text. Contract content: never log it.
  def snippet
    text_page.text[start_offset...end_offset]
  end

  def readonly?
    persisted? || super
  end
end
