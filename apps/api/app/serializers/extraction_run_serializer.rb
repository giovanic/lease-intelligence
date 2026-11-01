# Explicit JSON shape for an ExtractionRun (docs/adr/0017). The summary —
# status, counts, error code, timestamps — is embedded in the version JSON;
# `with_fields: true` adds the candidate fields and their evidence for
# GET /api/v1/extraction_runs/:id. Provider, model and token usage stay
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

    summary.merge(fields: @run.fields.map { |field| ExtractedFieldSerializer.new(field).as_json })
  end
end
