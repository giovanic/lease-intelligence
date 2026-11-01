module FieldExtraction
  # Last step of ExtractContractFieldsJob, in the tenant context: stores the
  # outcome of ExtractFields on the run — every candidate with its evidence
  # plus `succeeded`, model version and usage in one transaction, or
  # `failed` with the error code. A run that is already finished is left
  # alone (a duplicate job, or one closed as abandoned while this one was
  # still going), so it is never written twice.
  #
  # `result`: the ServiceResult of ExtractFields.
  # Returns success(ExtractionRun) | failure("finished").
  class RecordOutcome
    def self.call(run_id:, result:)
      ExtractionRun.transaction(requires_new: true) do
        run = ExtractionRun.lock.find(run_id)
        next ServiceResult.failure("finished") if run.finished?

        result.success? ? succeed(run, result.value) : record_failure(run, result.error)
        ServiceResult.success(run)
      end
    end

    def self.succeed(run, extracted)
      now = Time.current
      candidates = extracted.validated.candidates
      # One INSERT per row, not insert_all: insert_all inlines values as SQL
      # literals, which a debug-level log prints; as binds `value_text` and
      # `value_tax_id` are masked by filter_parameters.
      candidates.each_with_index do |candidate, position|
        field = ExtractedField.create!(tenant_id: run.tenant_id, extraction_run: run, position: position,
          field_key: candidate.key, value_type: candidate.value_type, created_at: now, **candidate.attributes)
        candidate.evidence.each do |span|
          EvidenceReference.create!(tenant_id: run.tenant_id, extracted_field: field, text_page_id: span.text_page_id,
            page_number: span.page_number, start_offset: span.start_offset, end_offset: span.end_offset,
            created_at: now)
        end
      end

      usage = extracted.usage
      run.update!(
        status: :succeeded, model_version: extracted.model_version, field_count: candidates.size,
        rejected_field_count: extracted.validated.rejected_count, input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens, cache_read_input_tokens: usage.cache_read_input_tokens,
        cache_creation_input_tokens: usage.cache_creation_input_tokens, duration_ms: extracted.duration_ms,
        started_at: run.started_at || now, finished_at: now
      )
    end

    def self.record_failure(run, error_code)
      run.update!(status: :failed, error_code: error_code, finished_at: Time.current)
    end
    private_class_method :succeed, :record_failure
  end
end
