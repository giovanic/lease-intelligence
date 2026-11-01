# Fixtures for the AI field extraction specs (docs/adr/0017).
module FieldExtractionHelpers
  # Stands in for an LLM provider (Llm): returns `output` (a Hash, as parsed
  # from the provider's JSON), or raises `error` if given. Records what it
  # was asked, so specs can check the prompt's structure.
  class FakeLlm
    attr_reader :requests

    def initialize(output = nil, error: nil, model_version: "fake-model-2026", max_input_characters: 1_000_000,
      external: false)
      @output = output
      @error = error
      @model_version = model_version
      @max_input_characters = max_input_characters
      @external = external
      @requests = []
    end

    attr_reader :max_input_characters

    def name = "fake"
    def model = "fake-model"
    def effort = "high"
    def external? = @external

    def extract(instructions:, document:, schema:)
      @requests << { instructions: instructions, document: document, schema: schema }
      raise @error if @error

      Llm::Result.new(output: @output || FieldExtractionHelpers.empty_output, model_version: @model_version,
        usage: Llm::Usage.new(input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 0,
          cache_creation_input_tokens: 800),
        duration_ms: 1500)
    end
  end

  module_function

  # An answer with every catalog key and no candidates.
  def empty_output
    FieldExtraction::Catalog.keys.index_with { [] }
  end

  # An answer with the given candidates: { "monthly_rent" => [candidate, ...] }.
  def output_with(candidates)
    empty_output.merge(candidates)
  end

  def candidate(value, page:, quote:)
    { "value" => value, "evidence" => [ { "page" => page, "quote" => quote } ] }
  end
end

RSpec.configure do |config|
  config.include FieldExtractionHelpers

  # No spec ever reaches the real provider, even on a machine with
  # ANTHROPIC_API_KEY set: the feature is off unless a spec opts in with a
  # FakeLlm (spec/services/llm/llm_spec.rb covers Llm.provider itself).
  config.before do |example|
    allow(Llm).to receive(:provider).and_return(nil) unless example.metadata[:real_llm_provider_lookup]
  end
end
