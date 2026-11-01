module FieldExtraction
  # Schema and evidence validation of a provider answer (docs/adr/0011,
  # docs/adr/0017 "Validation and evidence"). Pure — no database, no
  # provider: it gets the parsed answer and the pages the run read.
  #
  # A candidate is kept only if its value fits Catalog (type, vocabulary,
  # range, length, decimal format, cap per field) and at least one of its
  # quotes is found on the cited page of that exact text. A quote is found
  # when it matches the page with runs of whitespace collapsed on both
  # sides; its span is mapped back to character offsets in the stored page
  # text. Everything else is counted in `rejected_count` and dropped.
  #
  # success(Validated) | failure("invalid_output") when the answer does not
  # even have the schema's shape (structured outputs should prevent that).
  class ValidateOutput
    Span = Data.define(:text_page_id, :page_number, :start_offset, :end_offset)
    Candidate = Data.define(:key, :value_type, :attributes, :evidence)
    Validated = Data.define(:candidates, :rejected_count)

    WHITESPACE = /[[:space:]]/
    TAX_ID_PUNCTUATION = %r{[.\-/[:space:]]}
    TAX_ID_FORMAT = /\A(\d{11}|\d{14})\z/

    def self.call(output:, pages:)
      new(pages).call(output)
    end

    # `pages`: objects with id, number and text (StartRun::Page).
    def initialize(pages)
      @pages = pages.index_by(&:number)
      @collapsed = {}
    end

    def call(output)
      return invalid unless output.is_a?(Hash) && output.values.all?(Array)

      candidates = []
      rejected = output.except(*Catalog.keys).values.sum(&:size)
      Catalog::FIELDS.each do |field|
        Array(output[field.key]).each_with_index do |entry, index|
          candidate = candidate(field, entry) if index < field.max
          candidate ? candidates << candidate : rejected += 1
        end
      end
      ServiceResult.success(Validated.new(candidates: candidates, rejected_count: rejected))
    end

    private

    def invalid
      ServiceResult.failure("invalid_output")
    end

    def candidate(field, entry)
      return unless entry.is_a?(Hash)

      attributes = value_attributes(field, entry["value"])
      return if attributes.nil?

      evidence = evidence(entry["evidence"])
      return if evidence.empty?

      Candidate.new(key: field.key, value_type: field.type, attributes: attributes, evidence: evidence)
    end

    def value_attributes(field, value)
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

    # The amount stays a string until it becomes a BigDecimal: never a Float.
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

    def evidence(entries)
      return [] unless entries.is_a?(Array)

      entries.first(Catalog::MAX_EVIDENCE_PER_FIELD).filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["page"].is_a?(Integer) && entry["quote"].is_a?(String)

        page = @pages[entry["page"]]
        locate(page, Prompt.unescape(entry["quote"])) if page
      end.uniq
    end

    def locate(page, quote)
      needle = quote.delete("\u0000").unicode_normalize(:nfc).gsub(/[[:space:]]+/, " ").strip
      return if needle.delete(" ").length < Catalog::MIN_QUOTE_CHARACTERS
      return if needle.length > Catalog::MAX_QUOTE_CHARACTERS

      haystack, offsets = collapsed(page)
      start = haystack.index(needle)
      return if start.nil?

      Span.new(text_page_id: page.id, page_number: page.number, start_offset: offsets[start],
        end_offset: offsets[start + needle.length - 1] + 1)
    end

    # The page text with each run of whitespace collapsed to one space, and
    # for every character of it the offset of its source character.
    def collapsed(page)
      @collapsed[page.number] ||= begin
        haystack = +""
        offsets = []
        in_space = false
        page.text.each_char.with_index do |char, offset|
          space = char.match?(WHITESPACE)
          next if space && in_space

          haystack << (space ? " " : char)
          offsets << offset
          in_space = space
        end
        [ haystack, offsets ]
      end
    end
  end
end
