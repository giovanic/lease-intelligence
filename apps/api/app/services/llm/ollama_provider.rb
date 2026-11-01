require "net/http"

module Llm
  # A local open-weight model served by Ollama (docs/adr/0018): no per-token
  # cost, and the contract text stays on hosts we operate. One
  # non-streamed `POST /api/chat` per extraction: instructions as the
  # `system` message, the document alone as the `user` message, the answer
  # constrained to `schema` through `format`, temperature 0.
  #
  # Cloud models (`…:cloud`, `…-cloud`) run on ollama.com, so they are
  # refused here: a configuration slip must not route contracts outside.
  # Failures map to Llm errors with fixed messages and no `cause`.
  class OllamaProvider
    NAME = "ollama".freeze
    EFFORT = "n/a".freeze
    DEFAULT_URL = "http://127.0.0.1:11434".freeze
    DEFAULT_MODEL = "qwen2.5:7b".freeze
    DEFAULT_NUM_CTX = 32_768
    # Context kept for the instructions and the JSON answer; the rest is for
    # the document, at a conservative 3 characters per token (Portuguese).
    RESERVED_TOKENS = 8_192
    CHARACTERS_PER_TOKEN = 3
    CLOUD_MODEL = /[:-]cloud\z/

    attr_reader :model

    def self.from_env
      new(url: ENV.fetch("OLLAMA_URL", DEFAULT_URL), model: ENV.fetch("OLLAMA_MODEL", DEFAULT_MODEL),
        num_ctx: Integer(ENV.fetch("OLLAMA_NUM_CTX", DEFAULT_NUM_CTX.to_s)))
    end

    def initialize(url:, model:, num_ctx:, transport: nil)
      raise ArgumentError, "Ollama cloud models run outside our infrastructure: #{model}" if model.match?(CLOUD_MODEL)
      raise ArgumentError, "OLLAMA_NUM_CTX must leave room for the document" if num_ctx <= RESERVED_TOKENS

      @model = model
      @num_ctx = num_ctx
      @transport = transport || Transport.new(url)
    end

    def name = NAME
    def effort = EFFORT
    def external? = false

    # Ollama silently drops the start of a prompt longer than num_ctx: longer
    # text must fail as text_too_long instead (ExtractFields).
    def max_input_characters
      (@num_ctx - RESERVED_TOKENS) * CHARACTERS_PER_TOKEN
    end

    def extract(instructions:, document:, schema:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = @transport.post("/api/chat", request_body(instructions, document, schema))
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      raise TruncatedError, "provider answer truncated" if body["done_reason"] == "length"

      Result.new(output: parse(body.dig("message", "content")), model_version: model_version, duration_ms: duration_ms,
        usage: Usage.new(input_tokens: body["prompt_eval_count"], output_tokens: body["eval_count"],
          cache_read_input_tokens: nil, cache_creation_input_tokens: nil))
    end

    private

    def request_body(instructions, document, schema)
      {
        model: @model,
        stream: false,
        format: schema,
        options: { temperature: 0, num_ctx: @num_ctx },
        messages: [ { role: "system", content: instructions }, { role: "user", content: document } ]
      }
    end

    def parse(text)
      output = JSON.parse(text.to_s)
      raise InvalidOutputError, "provider answer is not a JSON object" unless output.is_a?(Hash)

      output
    rescue JSON::ParserError
      raise InvalidOutputError, "provider answer is not valid JSON", cause: nil
    end

    # "qwen2.5:7b@845dbda0ea48": the digest shows when a tag was re-pulled
    # with different weights.
    def model_version
      entry = Array(@transport.get("/api/tags")["models"]).find { |model| model["name"] == @model }
      digest = entry&.dig("digest").to_s
      digest.empty? ? @model : "#{@model}@#{digest[0, 12]}"
    end

    # JSON over HTTP to the Ollama server. Every failure becomes an Llm
    # error with a fixed message (the server's body could echo the prompt).
    class Transport
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 600 # seconds: a long contract on a small GPU

      CONNECTION_ERRORS = [
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE,
        SocketError, EOFError, IOError, Net::OpenTimeout, Net::HTTPBadResponse, OpenSSL::SSL::SSLError
      ].freeze

      def initialize(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        @uri = URI(url)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def get(path)
        perform(Net::HTTP::Get.new(path))
      end

      def post(path, payload)
        request = Net::HTTP::Post.new(path, "Content-Type" => "application/json")
        request.body = JSON.generate(payload)
        perform(request)
      end

      private

      def perform(request)
        response = http.request(request)
        # 404 is also what Ollama answers for a model that is not pulled.
        raise UnavailableError, "provider answered HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue Net::ReadTimeout
        raise TimeoutError, "provider request timed out", cause: nil
      rescue JSON::ParserError, *CONNECTION_ERRORS
        raise UnavailableError, "provider unavailable", cause: nil
      end

      def http
        Net::HTTP.new(@uri.host, @uri.port).tap do |http|
          http.use_ssl = @uri.scheme == "https"
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
        end
      end
    end
  end
end
