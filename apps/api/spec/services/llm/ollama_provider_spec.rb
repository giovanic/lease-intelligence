require "rails_helper"
require "socket"

# The local-model adapter (docs/adr/0018). The provider's logic runs against
# a stand-in transport; the transport itself runs against real local
# sockets (refused port, a server that never answers, one that answers 404),
# so no Ollama is needed.
module OllamaProviderSpec
  # Records requests; answers /api/chat with `chat` and /api/tags with `tags`.
  class FakeOllamaTransport
    attr_reader :posts

    def initialize(chat:, tags: { "models" => [ { "name" => "qwen2.5:7b", "digest" => "845dbda0ea48a1b2c3d4" } ] })
      @chat = chat
      @tags = tags
      @posts = []
    end

    def post(path, payload)
      @posts << [ path, payload ]
      @chat
    end

    def get(_path) = @tags
  end
end

RSpec.describe Llm::OllamaProvider do
  let(:schema) { FieldExtraction::Catalog.schema }
  let(:answer) { { "term_months" => [] } }

  def chat(content: answer.to_json, done_reason: "stop")
    { "model" => "qwen2.5:7b", "message" => { "role" => "assistant", "content" => content }, "done" => true,
      "done_reason" => done_reason, "prompt_eval_count" => 2100, "eval_count" => 340 }
  end

  def provider(transport, model: "qwen2.5:7b", num_ctx: 32_768)
    described_class.new(url: "http://127.0.0.1:11434", model: model, num_ctx: num_ctx, transport: transport)
  end

  def extract(transport)
    provider(transport).extract(instructions: "INSTRUÇÕES", document: "<document>x</document>", schema: schema)
  end

  it "sends instructions as the system message, the document alone as the user message, and the schema as format" do
    transport = OllamaProviderSpec::FakeOllamaTransport.new(chat: chat)

    extract(transport)

    path, payload = transport.posts.sole
    expect(path).to eq("/api/chat")
    expect(payload).to eq(
      model: "qwen2.5:7b", stream: false, format: schema, options: { temperature: 0, num_ctx: 32_768 },
      messages: [ { role: "system", content: "INSTRUÇÕES" }, { role: "user", content: "<document>x</document>" } ]
    )
  end

  it "returns the parsed answer, the model with its digest, and the token counts" do
    result = extract(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat))

    expect(result.output).to eq(answer)
    expect(result.model_version).to eq("qwen2.5:7b@845dbda0ea48")
    expect(result.usage).to eq(Llm::Usage.new(input_tokens: 2100, output_tokens: 340, cache_read_input_tokens: nil,
      cache_creation_input_tokens: nil))
  end

  it "records the bare model name when the server does not list it" do
    result = extract(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat, tags: { "models" => [] }))

    expect(result.model_version).to eq("qwen2.5:7b")
  end

  it "raises TruncatedError when the answer hit the context limit" do
    expect { extract(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat(done_reason: "length"))) }.to raise_error(Llm::TruncatedError)
  end

  it "raises InvalidOutputError for content that is not a JSON object" do
    expect { extract(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat(content: "Segue o JSON:"))) }.to raise_error(Llm::InvalidOutputError)
    expect { extract(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat(content: "[]"))) }.to raise_error(Llm::InvalidOutputError)
  end

  it "identifies itself as local, with an input limit derived from the context size" do
    local = provider(OllamaProviderSpec::FakeOllamaTransport.new(chat: chat), num_ctx: 32_768)

    expect([ local.name, local.model, local.effort, local.external? ]).to eq([ "ollama", "qwen2.5:7b", "n/a", false ])
    expect(local.max_input_characters).to eq((32_768 - 8_192) * 3)
  end

  it "refuses Ollama cloud models, which would send contracts outside our infrastructure" do
    %w[kimi-k2-thinking:cloud gpt-oss:120b-cloud].each do |model|
      expect { provider(nil, model: model) }.to raise_error(ArgumentError, /cloud/)
    end
  end

  it "refuses a context too small to hold any document" do
    expect { provider(nil, num_ctx: 4_096) }.to raise_error(ArgumentError, /OLLAMA_NUM_CTX/)
  end

  describe Llm::OllamaProvider::Transport do
    # A one-shot local HTTP server: `reply` is the raw response, or nil to
    # accept the connection and never answer.
    def with_server(reply)
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        client = server.accept
        client.readpartial(65_536)
        reply ? client.write(reply) : sleep(2)
        client.close
      rescue IOError, Errno::ECONNRESET
        nil
      end
      yield "http://127.0.0.1:#{server.addr[1]}"
    ensure
      thread&.kill
      server&.close
    end

    def http_response(status, body)
      "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    end

    it "posts JSON and parses the JSON answer" do
      with_server(http_response("200 OK", '{"done":true}')) do |url|
        expect(described_class.new(url).post("/api/chat", { "a" => 1 })).to eq("done" => true)
      end
    end

    it "maps a refused connection to UnavailableError" do
      port = TCPServer.new("127.0.0.1", 0).then { |server| server.addr[1].tap { server.close } }

      expect { described_class.new("http://127.0.0.1:#{port}").get("/api/tags") }
        .to raise_error(Llm::UnavailableError, "provider unavailable") { |error| expect(error.cause).to be_nil }
    end

    it "maps a server that never answers to TimeoutError" do
      with_server(nil) do |url|
        expect { described_class.new(url, read_timeout: 0.2).get("/api/tags") }.to raise_error(Llm::TimeoutError)
      end
    end

    it "maps an error status (e.g. a model that is not pulled) to UnavailableError, without the body" do
      with_server(http_response("404 Not Found", '{"error":"model \'contrato secreto\' not found"}')) do |url|
        expect { described_class.new(url).post("/api/chat", {}) }
          .to raise_error(Llm::UnavailableError, "provider answered HTTP 404")
      end
    end
  end
end

RSpec.describe "Llm.provider selection", :real_llm_provider_lookup do
  around do |example|
    saved = ENV.to_h.slice("LLM_PROVIDER", "ANTHROPIC_API_KEY", "OLLAMA_MODEL")
    %w[LLM_PROVIDER ANTHROPIC_API_KEY OLLAMA_MODEL].each { |name| ENV.delete(name) }
    Llm.remove_instance_variable(:@provider) if Llm.instance_variable_defined?(:@provider)
    example.run
  ensure
    %w[LLM_PROVIDER ANTHROPIC_API_KEY OLLAMA_MODEL].each { |name| ENV.delete(name) }
    ENV.update(saved)
    Llm.remove_instance_variable(:@provider) if Llm.instance_variable_defined?(:@provider)
  end

  before { allow(Rails.application.credentials).to receive(:dig).with(:anthropic, :api_key).and_return(nil) }

  it "uses the local Ollama adapter with LLM_PROVIDER=ollama, no key needed" do
    ENV["LLM_PROVIDER"] = "ollama"

    expect(Llm.provider).to be_a(Llm::OllamaProvider).and(have_attributes(model: "qwen2.5:7b"))
  end

  it "refuses an Ollama cloud model from the environment" do
    ENV.update("LLM_PROVIDER" => "ollama", "OLLAMA_MODEL" => "deepseek-v4-flash:cloud")

    expect { Llm.provider }.to raise_error(ArgumentError, /cloud/)
  end

  it "is off with LLM_PROVIDER=anthropic but no key" do
    ENV["LLM_PROVIDER"] = "anthropic"

    expect(Llm.provider).to be_nil
  end

  it "rejects an unknown provider name" do
    ENV["LLM_PROVIDER"] = "gpt"

    expect { Llm.provider }.to raise_error(ArgumentError, /LLM_PROVIDER/)
  end
end
