module FieldExtraction
  # The provider call and its validation (docs/adr/0017). No database
  # access — ExtractContractFieldsJob runs this outside any transaction,
  # since the call can take minutes.
  #
  # Expected provider failures become an error code of
  # ExtractionRun::ERROR_CODES. A plain Llm::Error (a request the provider
  # rejects as malformed) or anything unexpected is raised: the job retries
  # and then records internal_error.
  #
  # success(Extracted) | failure(error code)
  class ExtractFields
    Extracted = Data.define(:validated, :model_version, :usage, :duration_ms)

    LLM_ERROR_CODES = {
      Llm::RateLimitedError => "rate_limited",
      Llm::UnavailableError => "provider_unavailable",
      Llm::TimeoutError => "timeout",
      Llm::TruncatedError => "output_truncated",
      Llm::RefusedError => "refused",
      Llm::InvalidOutputError => "invalid_output"
    }.freeze

    # `pages`: [StartRun::Page].
    def self.call(pages:, provider:)
      return ServiceResult.failure("text_too_long") if pages.sum { |page| page.text.length } > provider.max_input_characters

      result = provider.extract(instructions: Prompt::INSTRUCTIONS, document: Prompt.document(pages),
        schema: Catalog.schema)
      validated = ValidateOutput.call(output: result.output, pages: pages)
      return validated if validated.failure?

      ServiceResult.success(Extracted.new(validated: validated.value, model_version: result.model_version,
        usage: result.usage, duration_ms: result.duration_ms))
    rescue *LLM_ERROR_CODES.keys => error
      ServiceResult.failure(LLM_ERROR_CODES.fetch(error.class))
    end
  end
end
