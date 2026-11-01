module ContractReview
  # Records a reviewer's decision on one AI-extracted field
  # (docs/adr/0012, docs/adr/0019). Must run in the field's tenant context;
  # authorization is the controller's (ReviewDecisionPolicy).
  #
  # - `decision`: "approved" | "corrected" | "rejected".
  # - `value`: only for "corrected", in the shape the run JSON shows for the
  #   field's value_type ({ "date" => ... }, { "integer" => ... },
  #   { "amount", "currency" }, { "option" => ... }, { "text" => ... },
  #   { "name", "tax_id" }), validated by the same rules as AI output
  #   (FieldExtraction::FieldValue).
  # - `reason`: optional free text (≤ 1 000 chars), stripped.
  #
  # Only fields of the version's latest succeeded run can be decided.
  #
  # success(ReviewDecision) | failure("stale_run") | failure({ attribute => [messages] })
  class RecordDecision
    # The run JSON's value shape -> FieldValue's raw shape, per value_type.
    RAW_VALUE = {
      "date" => ->(value) { value["date"] },
      "integer" => ->(value) { value["integer"] },
      "option" => ->(value) { value["option"] },
      "text" => ->(value) { value["text"] },
      "money" => ->(value) { value.slice("amount", "currency") },
      "party" => ->(value) { value.slice("name", "tax_id") }
    }.freeze

    def self.call(field:, decision:, value:, reason:, reviewed_by:)
      new(field).call(decision: decision, value: value, reason: reason, reviewed_by: reviewed_by)
    end

    def initialize(field)
      @field = field
    end

    def call(decision:, value:, reason:, reviewed_by:)
      return ServiceResult.failure("decision" => [ "is not included in the list" ]) unless ReviewDecision.decisions.key?(decision)
      return ServiceResult.failure("stale_run") unless latest_run?

      reason = reason.to_s.delete("\u0000").strip.presence
      return ServiceResult.failure("reason" => [ "is too long" ]) if reason && reason.length > ReviewDecision::REASON_MAX_LENGTH

      attributes = value_attributes(decision, value)
      return attributes if attributes.is_a?(ServiceResult)

      ServiceResult.success(ReviewDecision.create!(
        tenant_id: @field.tenant_id, extracted_field: @field, value_type: @field.value_type, decision: decision,
        reason: reason, reviewed_by: reviewed_by, created_at: Time.current, **attributes
      ))
    end

    private

    def latest_run?
      run = @field.extraction_run
      latest = ExtractionRun.succeeded.where(document_version_id: run.document_version_id)
        .order(created_at: :desc, id: :desc).first
      latest&.id == run.id
    end

    def value_attributes(decision, value)
      if decision != "corrected"
        return value.blank? ? {} : ServiceResult.failure("value" => [ "must be empty unless the decision is corrected" ])
      end

      catalog_field = FieldExtraction::Catalog::BY_KEY[@field.field_key]
      attributes = catalog_field && value.is_a?(Hash) &&
        FieldExtraction::FieldValue.attributes(catalog_field, RAW_VALUE.fetch(@field.value_type).call(value.stringify_keys))
      attributes || ServiceResult.failure("value" => [ "is invalid for #{@field.field_key}" ])
    end
  end
end
