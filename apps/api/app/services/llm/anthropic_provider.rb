module Llm
  # Claude through the official `anthropic` gem (docs/adr/0017). One
  # streamed Messages request per extraction: instructions in `system`
  # (cached), the document alone in the user turn, the answer constrained to
  # `schema` by structured outputs, no tools. A refusal is retried
  # server-side on Anthropic's default fallback model; `model_version` is
  # the model that actually answered.
  #
  # The client retries 429/5xx/connection errors itself (MAX_RETRIES, with
  # backoff); what still fails is mapped to an Llm error with a fixed
  # message and no `cause`, so neither the vendor's message nor the request
  # reaches a log or error tracker.
  class AnthropicProvider
    NAME = "anthropic".freeze
    MODEL = "claude-opus-5-5".freeze
    EFFORT = "high".freeze
    # Room for adaptive thinking plus the JSON answer; streaming keeps a
    # large value safe from HTTP timeouts.
    MAX_TOKENS = 32_000
    TIMEOUT = 900 # seconds, per attempt
    MAX_RETRIES = 2
    FALLBACK_BETA = :"server-side-fallback-2026-07-01"

    UNAVAILABLE_TYPES = %i[overloaded_error api_error].freeze

    def initialize(api_key: nil, client: nil)
      @client = client || Anthropic::Client.new(api_key: api_key, timeout: TIMEOUT, max_retries: MAX_RETRIES)
    end

    def name = NAME
    def model = MODEL
    def effort = EFFORT

    def extract(instructions:, document:, schema:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      message = request(instructions, document, schema)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      check_stop_reason!(message)
      Result.new(output: parse(message), model_version: message.model.to_s, usage: usage(message.usage),
        duration_ms: duration_ms)
    end

    private

    def request(instructions, document, schema)
      @client.beta.messages.stream(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system_: [ { type: "text", text: instructions, cache_control: { type: "ephemeral" } } ],
        messages: [ { role: "user", content: document } ],
        thinking: { type: "adaptive" },
        output_config: { effort: EFFORT, format: { type: "json_schema", schema: schema } },
        fallbacks: :default,
        betas: [ FALLBACK_BETA ]
      ).accumulated_message
    rescue Anthropic::Errors::RateLimitError
      raise RateLimitedError, "rate limited by the provider", cause: nil
    rescue Anthropic::Errors::APITimeoutError
      raise TimeoutError, "provider request timed out", cause: nil
    rescue Anthropic::Errors::InternalServerError, Anthropic::Errors::APIConnectionError,
      Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError
      raise UnavailableError, "provider unavailable", cause: nil
    rescue Anthropic::Errors::APIStatusError => error
      # A mid-stream `error` event arrives with the stream's HTTP status
      # (200): classify it by its type.
      raise RateLimitedError, "rate limited by the provider", cause: nil if error.type == :rate_limit_error
      raise UnavailableError, "provider unavailable", cause: nil if UNAVAILABLE_TYPES.include?(error.type)

      # Anything else (400, 404, ...) is a bug on our side: a plain Llm::Error,
      # so the job retries and then records internal_error.
      raise Error, "provider rejected the request (status #{error.status})", cause: nil
    rescue Error
      raise
    rescue StandardError => error
      # Any other failure inside the client (e.g. a JSON::ParserError on a
      # stream chunk) could carry answer text in its message, which the job's
      # retry log would print: keep only the class.
      raise Error, "unexpected provider client error (#{error.class})", cause: nil
    end

    def check_stop_reason!(message)
      case message.stop_reason
      when :max_tokens then raise TruncatedError, "provider answer truncated"
      when :refusal then raise RefusedError, "provider refused"
      end
    end

    def parse(message)
      text = message.content.select { |block| block.type == :text }.map(&:text).join
      output = JSON.parse(text)
      raise InvalidOutputError, "provider answer is not a JSON object" unless output.is_a?(Hash)

      output
    rescue JSON::ParserError
      raise InvalidOutputError, "provider answer is not valid JSON", cause: nil
    end

    def usage(usage)
      Usage.new(input_tokens: usage.input_tokens, output_tokens: usage.output_tokens,
        cache_read_input_tokens: usage.cache_read_input_tokens,
        cache_creation_input_tokens: usage.cache_creation_input_tokens)
    end
  end
end
