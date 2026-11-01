module FieldExtraction
  # The rules a value must satisfy to be stored for a catalog field
  # (docs/adr/0017, docs/adr/0019) — the same for a model's answer
  # (ValidateOutput) and a reviewer's correction (ContractReview::RecordDecision).
  # Pure: turns a raw value into the typed column attributes of
  # extracted_fields / review_decisions, or nil when it does not fit.
  #
  # Raw shapes, per Catalog type: date "YYYY-MM-DD"; integer Integer;
  # money { "amount" => "12000.00", "currency" => "BRL" } (the amount stays a
  # string until it becomes a BigDecimal — never a Float); option a code of
  # the field's options; text String; party { "name" => ..., "tax_id" => CPF/CNPJ or nil }.
  module FieldValue
    TAX_ID_PUNCTUATION = %r{[.\-/[:space:]]}
    TAX_ID_FORMAT = /\A(\d{11}|\d{14})\z/

    module_function

    # `field`: a Catalog::Field. Returns a Hash of value_* attributes, or nil.
    def attributes(field, value)
      case field.type
      when "date" then date(value)&.then { |date| { value_date: date } }
      when "integer" then integer(value, field.range)&.then { |integer| { value_integer: integer } }
      when "money" then money(value)
      when "option" then { value_text: value } if field.options.include?(value)
      when "text" then text(value, Catalog::TEXT_MAX_LENGTH)&.then { |text| { value_text: text } }
      when "party" then party(value)
      end
    end

    def date(value)
      return unless value.is_a?(String) && value.match?(Catalog::DATE_FORMAT)

      date = Date.iso8601(value)
      date if Catalog::DATE_YEARS.cover?(date.year)
    rescue Date::Error
      nil
    end

    def integer(value, range)
      value if value.is_a?(Integer) && range.cover?(value)
    end

    def money(value)
      return unless value.is_a?(Hash)

      amount = value["amount"]
      currency = value["currency"]
      return unless amount.is_a?(String) && amount.match?(Catalog::AMOUNT_FORMAT)
      return unless currency.is_a?(String) && currency.match?(Catalog::CURRENCY_FORMAT)

      { value_amount: BigDecimal(amount), value_currency: currency }
    end

    def party(value)
      return unless value.is_a?(Hash)

      name = text(value["name"], Catalog::PARTY_NAME_MAX_LENGTH)
      return if name.nil?

      tax_id = value["tax_id"]
      return { value_text: name, value_tax_id: nil } if tax_id.nil? || (tax_id.is_a?(String) && tax_id.strip.empty?)
      return unless tax_id.is_a?(String)

      digits = tax_id.gsub(TAX_ID_PUNCTUATION, "")
      { value_text: name, value_tax_id: digits } if digits.match?(TAX_ID_FORMAT)
    end

    def text(value, max_length)
      return unless value.is_a?(String)

      text = value.delete("\u0000").unicode_normalize(:nfc).strip
      text if text.length.between?(1, max_length)
    end
  end
end
