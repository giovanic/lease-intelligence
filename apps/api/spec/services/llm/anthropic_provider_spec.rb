require "rails_helper"

# The Claude adapter (docs/adr/0017), against a stand-in for the gem's
# client: no network. Checks the request's structure (instructions in
# system, document alone in the user turn, schema-constrained output) and
# that every vendor failure becomes an Llm error with a fixed message.
module AnthropicProviderSpec
  TextBlock = Struct.new(:type, :text)
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens)
  Message = Struct.new(:model, :stop_reason, :content, :usage)

  # client.beta.messages.stream(params).accumulated_message
  class FakeClient
    attr_reader :params

    def initialize(message: nil, error: nil)
      @message = message
      @error = error
    end

    def beta = self
    def messages = self

    def stream(params)
      @params = params
      raise @error if @error

      Struct.new(:accumulated_message).new(@message)
    end
  end
end

RSpec.describe Llm::AnthropicProvider do
  let(:schema) { FieldExtraction::Catalog.schema }
  let(:answer) { { "term_months" => [] } }

  def message(text: answer.to_json, stop_reason: :end_turn, model: :"claude-opus-5-5")
    AnthropicProviderSpec::Message.new(model, stop_reason, [ AnthropicProviderSpec::TextBlock.new(:thinking, nil), AnthropicProviderSpec::TextBlock.new(:text, text) ],
      AnthropicProviderSpec::Usage.new(5000, 700, 4000, 0))
  end

  def extract(client)
    described_class.new(client: client).extract(instructions: "INSTRUÇÕES", document: "<document>x</document>",
      schema: schema)
  end

  def api_error(klass, status)
    klass.new(url: URI("https://api.anthropic.com/v1/messages"), status: status, headers: {},
      body: { error: { message: "eco do contrato: aluguel R$ 10.000,00" } }, request: nil, response: nil,
      message: "eco do contrato: aluguel R$ 10.000,00")
  end

  # What a mid-stream `error` event becomes in the gem (HTTP status of the stream: 200).
  def stream_error(type)
    Anthropic::Errors::APIStatusError.for(url: URI("https://api.anthropic.com/v1/messages"), status: 200, headers: {},
      body: { type: "error", error: { type: type, message: "eco do contrato" } }, request: nil, response: nil)
  end

  it "sends instructions as cached system text, the document alone as the user turn, and the schema as output format" do
    client = AnthropicProviderSpec::FakeClient.new(message: message)

    extract(client)

    expect(client.params).to include(
      model: "claude-opus-5-5",
      max_tokens: described_class::MAX_TOKENS,
      system_: [ { type: "text", text: "INSTRUÇÕES", cache_control: { type: "ephemeral" } } ],
      messages: [ { role: "user", content: "<document>x</document>" } ],
      thinking: { type: "adaptive" },
      output_config: { effort: "high", format: { type: "json_schema", schema: schema } },
      fallbacks: :default,
      betas: [ :"server-side-fallback-2026-07-01" ]
    )
    expect(client.params).not_to include(:tools)
  end

  it "returns the parsed answer, the model that answered and the token usage" do
    result = extract(AnthropicProviderSpec::FakeClient.new(message: message(model: :"claude-opus-4-8")))

    expect(result.output).to eq(answer)
    expect(result.model_version).to eq("claude-opus-4-8")
    expect(result.usage).to eq(Llm::Usage.new(input_tokens: 5000, output_tokens: 700, cache_read_input_tokens: 4000,
      cache_creation_input_tokens: 0))
    expect(result.duration_ms).to be >= 0
  end

  it "identifies itself for the run" do
    provider = described_class.new(client: AnthropicProviderSpec::FakeClient.new)

    expect([ provider.name, provider.model, provider.effort ]).to eq(%w[anthropic claude-opus-5-5 high])
  end

  describe "answers that cannot be used" do
    it "raises TruncatedError at max_tokens and RefusedError on a refusal" do
      expect { extract(AnthropicProviderSpec::FakeClient.new(message: message(stop_reason: :max_tokens))) }.to raise_error(Llm::TruncatedError)
      expect { extract(AnthropicProviderSpec::FakeClient.new(message: message(stop_reason: :refusal))) }.to raise_error(Llm::RefusedError)
    end

    it "raises InvalidOutputError for text that is not a JSON object" do
      expect { extract(AnthropicProviderSpec::FakeClient.new(message: message(text: "Aqui estão os campos:"))) }
        .to raise_error(Llm::InvalidOutputError)
      expect { extract(AnthropicProviderSpec::FakeClient.new(message: message(text: "[]"))) }.to raise_error(Llm::InvalidOutputError)
    end
  end

  describe "provider failures" do
    {
      "a 429 after the client's retries" => [ -> { api_error(Anthropic::Errors::RateLimitError, 429) }, Llm::RateLimitedError ],
      "a 5xx/529" => [ -> { api_error(Anthropic::Errors::InternalServerError, 529) }, Llm::UnavailableError ],
      "a rejected credential" => [ -> { api_error(Anthropic::Errors::AuthenticationError, 401) }, Llm::UnavailableError ],
      "a connection error" => [ -> { Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com")) },
        Llm::UnavailableError ],
      "a timeout" => [ -> { Anthropic::Errors::APITimeoutError.new(url: URI("https://api.anthropic.com")) }, Llm::TimeoutError ],
      "an overloaded error mid-stream" => [ -> { stream_error("overloaded_error") }, Llm::UnavailableError ],
      "a rate limit error mid-stream" => [ -> { stream_error("rate_limit_error") }, Llm::RateLimitedError ]
    }.each do |label, (vendor_error, llm_error)|
      it "maps #{label} to #{llm_error}, with a fixed message and no cause" do
        expect { extract(AnthropicProviderSpec::FakeClient.new(error: instance_exec(&vendor_error))) }.to raise_error(llm_error) { |error|
          expect(error.message).not_to include("contrato")
          expect(error.cause).to be_nil
        }
      end
    end

    it "wraps any other client error without its message, which could carry answer text" do
      leaky = JSON::ParserError.new("unexpected token at 'Locador: João da Silva'")

      expect { extract(AnthropicProviderSpec::FakeClient.new(error: leaky)) }
        .to raise_error(Llm::Error, "unexpected provider client error (JSON::ParserError)") { |error|
          expect(error.cause).to be_nil
        }
    end

    it "raises a plain Llm::Error for a request the provider rejects (a bug on our side)" do
      expect { extract(AnthropicProviderSpec::FakeClient.new(error: api_error(Anthropic::Errors::BadRequestError, 400))) }
        .to raise_error(Llm::Error, "provider rejected the request (status 400)") { |error|
          expect(error.class).to eq(Llm::Error)
          expect(error.cause).to be_nil
        }
    end
  end
end

RSpec.describe Llm, :real_llm_provider_lookup do
  around do |example|
    Llm.remove_instance_variable(:@provider) if Llm.instance_variable_defined?(:@provider)
    original = ENV.delete("ANTHROPIC_API_KEY")
    example.run
  ensure
    ENV["ANTHROPIC_API_KEY"] = original
    Llm.remove_instance_variable(:@provider) if Llm.instance_variable_defined?(:@provider)
  end

  it "has no provider — the feature is off — without an API key" do
    allow(Rails.application.credentials).to receive(:dig).with(:anthropic, :api_key).and_return(nil)

    expect(Llm.provider).to be_nil
  end

  it "uses the Anthropic adapter when ANTHROPIC_API_KEY is set" do
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"

    expect(Llm.provider).to be_a(Llm::AnthropicProvider)
  end
end
