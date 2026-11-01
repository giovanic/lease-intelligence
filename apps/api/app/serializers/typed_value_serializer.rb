# The JSON shape of a typed value (docs/adr/0017, docs/adr/0019), shared by
# ExtractedField (the AI's value) and ReviewDecision (a reviewer's
# correction): one shape per value_type; money is a decimal string
# ("12000.00"), never a JSON number.
class TypedValueSerializer
  def initialize(record)
    @record = record
  end

  def as_json(*)
    case @record.value_type
    when "date" then { date: @record.value_date.iso8601 }
    when "integer" then { integer: @record.value_integer }
    when "money" then { amount: amount(@record.value_amount), currency: @record.value_currency }
    when "option" then { option: @record.value_text }
    when "text" then { text: @record.value_text }
    when "party" then { name: @record.value_text, tax_id: @record.value_tax_id }
    end
  end

  private

  # Two decimal places from the BigDecimal itself — format("%.2f") would go
  # through a Float.
  def amount(decimal)
    whole, fraction = decimal.round(2).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(2, "0")}"
  end
end
