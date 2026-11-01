# Explicit JSON shape for an ExtractionRun (docs/adr/0017). The summary —
# status, counts, error code, timestamps — is embedded in the version JSON;
# `with_fields: true` adds the candidate fields, their evidence and their
# latest review decision, plus `review_summary` (counts per current state,
# docs/adr/0019) and `document_version` (what the review screen shows next
# to the fields), for GET /api/v1/extraction_runs/:id. Provider, model and token usage stay
# internal (audit/evaluation data, not product data).
class ExtractionRunSerializer
  def initialize(run, with_fields: false)
    @run = run
    @with_fields = with_fields
  end

  def as_json(*)
    summary = {
      id: @run.id,
      document_version_id: @run.document_version_id,
      status: @run.status,
      field_count: @run.field_count,
      rejected_field_count: @run.rejected_field_count,
      error_code: @run.error_code,
      started_at: @run.started_at,
      finished_at: @run.finished_at,
      created_at: @run.created_at
    }
    return summary unless @with_fields

    fields = @run.fields.to_a
    summary.merge(fields: fields.map { |field| ExtractedFieldSerializer.new(field).as_json },
      review_summary: review_summary(fields), document_version: version_summary(@run.document_version))
  end

  private

  def version_summary(version)
    { id: version.id, contract_document_id: version.contract_document_id, version_number: version.version_number,
      original_filename: version.original_filename, content_type: version.content_type }
  end

  def review_summary(fields)
    states = fields.map { |field| field.review_decisions.last&.decision || "pending" }
    %w[approved corrected rejected pending].index_with { |state| states.count(state) }
  end
end
