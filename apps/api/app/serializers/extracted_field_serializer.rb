# Explicit JSON shape for an ExtractedField and its evidence (docs/adr/0017).
# A candidate read by AI, not a reviewed fact. `value` has one shape per
# `value_type`; money is a decimal string ("12000.00"), never a JSON
# number. Each evidence carries the quoted `snippet` (contract content,
# sliced from the stored page text) and the page's `source` (native/ocr).
class ExtractedFieldSerializer
  def initialize(field)
    @field = field
  end

  def as_json(*)
    {
      id: @field.id,
      key: @field.field_key,
      value_type: @field.value_type,
      value: value,
      evidence: @field.evidence_references.map { |evidence| evidence_json(evidence) }
    }
  end

  private

  def value
    case @field.value_type
    when "date" then { date: @field.value_date.iso8601 }
    when "integer" then { integer: @field.value_integer }
    when "money" then { amount: amount(@field.value_amount), currency: @field.value_currency }
    when "option" then { option: @field.value_text }
    when "text" then { text: @field.value_text }
    when "party" then { name: @field.value_text, tax_id: @field.value_tax_id }
    end
  end

  # Two decimal places from the BigDecimal itself — format("%.2f") would go
  # through a Float.
  def amount(decimal)
    whole, fraction = decimal.round(2).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(2, "0")}"
  end

  def evidence_json(evidence)
    {
      id: evidence.id,
      page_number: evidence.page_number,
      source: evidence.text_page.source,
      start_offset: evidence.start_offset,
      end_offset: evidence.end_offset,
      snippet: evidence.snippet
    }
  end
end
