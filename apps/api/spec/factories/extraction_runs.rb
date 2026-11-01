# AI field extraction rows (docs/adr/0017), written directly — normally
# FieldExtraction::RequestRun / RecordOutcome.
FactoryBot.define do
  # A pending run over a text extraction (and its version).
  factory :extraction_run do
    text_extraction factory: :document_text_extraction
    document_version { text_extraction.document_version }
    tenant { text_extraction.tenant }
    status { "pending" }
    provider { "fake" }
    model { "fake-model" }
    prompt_version { FieldExtraction::Prompt::VERSION }
    effort { "high" }
  end

  factory :extracted_field do
    extraction_run
    tenant { extraction_run.tenant }
    sequence(:position)
    field_key { "term_months" }
    value_type { "integer" }
    value_integer { 60 }
    created_at { Time.current }
  end

  factory :evidence_reference do
    extracted_field
    tenant { extracted_field.tenant }
    text_page do
      association :document_text_page, text_extraction: extracted_field.extraction_run.text_extraction,
        text: "Prazo de 60 meses"
    end
    page_number { text_page.page_number }
    start_offset { 0 }
    end_offset { 5 }
    created_at { Time.current }
  end
end
