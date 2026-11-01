# Explicit JSON shape for a ReviewDecision (docs/adr/0019). `value` is the
# corrected value (same shape as the field's), null unless `corrected`.
class ReviewDecisionSerializer
  def initialize(decision)
    @decision = decision
  end

  def as_json(*)
    {
      id: @decision.id,
      extracted_field_id: @decision.extracted_field_id,
      decision: @decision.decision,
      value: @decision.corrected? ? TypedValueSerializer.new(@decision).as_json : nil,
      reason: @decision.reason,
      reviewed_by: { id: @decision.reviewed_by.id, full_name: @decision.reviewed_by.full_name },
      created_at: @decision.created_at
    }
  end
end
