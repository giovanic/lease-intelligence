module FieldExtraction
  # The fields an ExtractionRun asks for (docs/adr/0017 "Field catalog v1"):
  # their value type, limits, and the JSON Schema the provider's answer must
  # follow. Changing a field, a limit or the schema is a new VERSION — it is
  # recorded on every run as its prompt version, so runs stay comparable.
  module Catalog
    VERSION = "lease-fields-v1".freeze

    Field = Data.define(:key, :type, :max, :options, :range)

    # Upper bounds that fit the columns and catch nonsense, not business rules.
    TEXT_MAX_LENGTH = 1_000
    PARTY_NAME_MAX_LENGTH = 300
    MAX_EVIDENCE_PER_FIELD = 3
    MIN_QUOTE_CHARACTERS = 4
    MAX_QUOTE_CHARACTERS = 2_000
    AMOUNT_FORMAT = /\A\d{1,13}(\.\d{1,2})?\z/
    CURRENCY_FORMAT = /\A[A-Z]{3}\z/
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
    DATE_YEARS = (1900..2200)

    # readjustment_index: IGP-M, IPCA, INPC, IGP-DI, IVAR (FGV's rent index)
    # or another index named in the contract.
    READJUSTMENT_INDEXES = %w[igp_m ipca inpc igp_di ivar other].freeze
    # guarantee_type, Lei 8.245/91 art. 37: caução, fiança, seguro-fiança,
    # título de capitalização (caução em títulos), cessão fiduciária de quotas
    # de fundo de investimento, or none.
    GUARANTEE_TYPES = %w[
      security_deposit personal_guarantee surety_insurance capitalization_bond investment_fund_assignment none
    ].freeze

    FIELDS = [
      Field.new(key: "signature_date", type: "date", max: 3, options: nil, range: nil),
      Field.new(key: "effective_date", type: "date", max: 3, options: nil, range: nil),
      Field.new(key: "commencement_date", type: "date", max: 3, options: nil, range: nil),
      Field.new(key: "expiration_date", type: "date", max: 3, options: nil, range: nil),
      Field.new(key: "term_months", type: "integer", max: 3, options: nil, range: 1..1_200),
      Field.new(key: "monthly_rent", type: "money", max: 3, options: nil, range: nil),
      Field.new(key: "rent_due_day", type: "integer", max: 3, options: nil, range: 1..31),
      Field.new(key: "readjustment_index", type: "option", max: 3, options: READJUSTMENT_INDEXES, range: nil),
      Field.new(key: "readjustment_frequency_months", type: "integer", max: 3, options: nil, range: 1..120),
      Field.new(key: "guarantee_type", type: "option", max: 3, options: GUARANTEE_TYPES, range: nil),
      Field.new(key: "security_deposit_amount", type: "money", max: 3, options: nil, range: nil),
      Field.new(key: "termination_notice_days", type: "integer", max: 3, options: nil, range: 0..3_650),
      Field.new(key: "renewal_terms", type: "text", max: 3, options: nil, range: nil),
      Field.new(key: "early_termination_penalty", type: "text", max: 3, options: nil, range: nil),
      Field.new(key: "lessor", type: "party", max: 10, options: nil, range: nil),
      Field.new(key: "lessee", type: "party", max: 10, options: nil, range: nil),
      Field.new(key: "guarantor", type: "party", max: 10, options: nil, range: nil)
    ].freeze

    BY_KEY = FIELDS.index_by(&:key).freeze

    module_function

    def fetch(key)
      BY_KEY.fetch(key)
    end

    def keys
      BY_KEY.keys
    end

    # One array per field (empty when the document does not state it); each
    # candidate is { value, evidence: [{ page, quote }] }. Structured outputs
    # cannot express lengths or ranges: ValidateOutput checks those.
    def schema
      @schema ||= {
        "type" => "object",
        "properties" => FIELDS.to_h { |field| [ field.key, { "type" => "array", "items" => candidate_schema(field) } ] },
        "required" => keys,
        "additionalProperties" => false
      }.freeze
    end

    def candidate_schema(field)
      {
        "type" => "object",
        "properties" => {
          "value" => value_schema(field),
          "evidence" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => { "page" => { "type" => "integer" }, "quote" => { "type" => "string" } },
              "required" => %w[page quote],
              "additionalProperties" => false
            }
          }
        },
        "required" => %w[value evidence],
        "additionalProperties" => false
      }
    end

    def value_schema(field)
      case field.type
      when "date" then { "type" => "string", "format" => "date" }
      when "integer" then { "type" => "integer" }
      when "text" then { "type" => "string" }
      when "option" then { "type" => "string", "enum" => field.options }
      when "money"
        object_schema("amount" => { "type" => "string" }, "currency" => { "type" => "string" })
      when "party"
        object_schema("name" => { "type" => "string" },
          "tax_id" => { "anyOf" => [ { "type" => "string" }, { "type" => "null" } ] })
      end
    end

    def object_schema(properties)
      { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false }
    end
  end
end
