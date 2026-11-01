# Explicit JSON shape for an ExtractedField and its evidence (docs/adr/0017).
# A candidate read by AI, not a reviewed fact. `value`: TypedValueSerializer.
# Each evidence carries the quoted `snippet` (contract content, sliced from
# the stored page text) and the page's `source` (native/ocr). `review` is
# the latest human decision, or null while pending; `review_count` how many
# decisions it has had (docs/adr/0019). Expects review_decisions preloaded.
class ExtractedFieldSerializer
  def initialize(field)
    @field = field
  end

  def as_json(*)
    {
      id: @field.id,
      key: @field.field_key,
      value_type: @field.value_type,
      value: TypedValueSerializer.new(@field).as_json,
      evidence: @field.evidence_references.map { |evidence| evidence_json(evidence) },
      review: @field.review_decisions.last&.then { |decision| ReviewDecisionSerializer.new(decision).as_json },
      review_count: @field.review_decisions.size
    }
  end

  private

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
