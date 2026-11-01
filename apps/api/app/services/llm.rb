# The internal LLM provider interface (docs/adr/0009-llm-provider-abstraction.md,
# docs/adr/0017-contract-field-extraction-claude.md). Pipeline code depends
# on this module only, never on a vendor SDK.
#
# A provider responds to:
#
#   name, model, effort -> String
#     Recorded on the ExtractionRun when it is requested.
#   extract(instructions:, document:, schema:) -> Llm::Result
#     `instructions` is trusted text for the system channel; `document` is
#     untrusted text for the user turn and must never be placed anywhere the
#     model treats as instructions; `schema` is the JSON Schema the answer
#     must follow. `output` is the parsed JSON object (a Hash, string keys).
#
# Failures raise one of the errors below, never a vendor error. Their
# messages are fixed strings: never put document content or provider
# output in them, they end up in logs.
module Llm
  Usage = Data.define(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens)
  Result = Data.define(:output, :model_version, :usage, :duration_ms)

  class Error < StandardError; end
  # The provider kept refusing for rate limits after its client's retries.
  class RateLimitedError < Error; end
  # 5xx/overloaded, connection errors, or a credential the provider rejects.
  class UnavailableError < Error; end
  # The request took longer than the provider's limit.
  class TimeoutError < Error; end
  # The answer was cut at the output token limit.
  class TruncatedError < Error; end
  # The model declined to answer.
  class RefusedError < Error; end
  # The answer is not a JSON object.
  class InvalidOutputError < Error; end

  module_function

  # The provider the pipeline uses, or nil when none is configured — then
  # the feature is off (no automatic runs, the manual request answers 503).
  # Anthropic is the only real one (ADR-0017); specs stub this.
  def provider
    return @provider if defined?(@provider) && @provider

    api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key).presence
    @provider = AnthropicProvider.new(api_key: api_key) if api_key
  end
end
