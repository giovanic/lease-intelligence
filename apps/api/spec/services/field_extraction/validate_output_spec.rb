require "rails_helper"

# Schema + evidence validation (docs/adr/0011, docs/adr/0017): pure, no
# database — pages are plain values like the ones StartRun returns.
RSpec.describe FieldExtraction::ValidateOutput do
  let(:page_one) do
    FieldExtraction::StartRun::Page.new(id: "page-1", number: 1, text: <<~TEXT.strip)
      CLÁUSULA 3ª - O aluguel mensal é de R$ 12.345,67 (doze mil),
      vencendo   todo dia 5 de cada mês.
      Locador: Imobiliária Alfa Ltda., CNPJ 12.345.678/0001-90.
    TEXT
  end
  let(:page_two) do
    FieldExtraction::StartRun::Page.new(id: "page-2", number: 2, text: "Reajuste anual pelo IGP-M & IPCA <limite>.")
  end
  let(:pages) { [ page_one, page_two ] }

  def validate(candidates)
    described_class.call(output: output_with(candidates), pages: pages)
  end

  def accepted(candidates)
    result = validate(candidates)
    expect(result).to be_success
    result.value
  end

  it "keeps a valid candidate with the offsets of its quote in the stored page text" do
    validated = accepted("monthly_rent" => [
      candidate({ "amount" => "12345.67", "currency" => "BRL" }, page: 1, quote: "aluguel mensal é de R$ 12.345,67")
    ])

    expect(validated.rejected_count).to eq(0)
    rent = validated.candidates.sole
    expect(rent).to have_attributes(key: "monthly_rent", value_type: "money",
      attributes: { value_amount: BigDecimal("12345.67"), value_currency: "BRL" })
    span = rent.evidence.sole
    expect(span).to have_attributes(text_page_id: "page-1", page_number: 1)
    expect(page_one.text[span.start_offset...span.end_offset]).to eq("aluguel mensal é de R$ 12.345,67")
  end

  it "finds a quote across collapsed whitespace and line breaks, mapping back to the original span" do
    span = accepted("rent_due_day" => [
      candidate(5, page: 1, quote: "(doze mil), vencendo todo dia 5")
    ]).candidates.sole.evidence.sole

    expect(page_one.text[span.start_offset...span.end_offset]).to eq("(doze mil),\nvencendo   todo dia 5")
  end

  it "unescapes the &, < and > the prompt escaped before looking the quote up" do
    span = accepted("readjustment_index" => [
      candidate("igp_m", page: 2, quote: "IGP-M &amp; IPCA &lt;limite&gt;")
    ]).candidates.sole.evidence.sole

    expect(page_two.text[span.start_offset...span.end_offset]).to eq("IGP-M & IPCA <limite>")
  end

  describe "evidence" do
    it "rejects a candidate whose quote is not on the cited page" do
      validated = accepted("rent_due_day" => [ candidate(5, page: 2, quote: "vencendo todo dia 5") ])

      expect(validated.candidates).to be_empty
      expect(validated.rejected_count).to eq(1)
    end

    it "rejects a paraphrased quote and a quote citing a page that does not exist" do
      validated = accepted("rent_due_day" => [
        candidate(5, page: 1, quote: "o vencimento é no dia cinco"),
        candidate(5, page: 9, quote: "vencendo todo dia 5")
      ])

      expect(validated.candidates).to be_empty
      expect(validated.rejected_count).to eq(2)
    end

    it "rejects a quote shorter than the minimum, even if it matches" do
      validated = accepted("rent_due_day" => [ candidate(5, page: 1, quote: " 5 ") ])

      expect(validated.rejected_count).to eq(1)
    end

    it "is case and accent sensitive: the quote must be copied as written" do
      validated = accepted("rent_due_day" => [ candidate(5, page: 1, quote: "VENCENDO TODO DIA 5") ])

      expect(validated.rejected_count).to eq(1)
    end

    it "keeps a candidate when one of its quotes is valid, dropping the invalid one" do
      entry = { "value" => 5, "evidence" => [
        { "page" => 1, "quote" => "inventado" }, { "page" => 1, "quote" => "todo dia 5 de cada mês" }
      ] }

      expect(accepted("rent_due_day" => [ entry ]).candidates.sole.evidence.size).to eq(1)
    end

    it "reads at most three quotes per candidate and stores a repeated one once" do
      quote = { "page" => 1, "quote" => "todo dia 5 de cada mês" }
      fourth = { "page" => 1, "quote" => "CLÁUSULA 3ª" }

      evidence = accepted("rent_due_day" => [ { "value" => 5, "evidence" => [ quote, quote, quote, fourth ] } ])
        .candidates.sole.evidence

      expect(evidence.size).to eq(1)
    end
  end

  describe "values" do
    def evidence_for(value, key)
      { key => [ candidate(value, page: 1, quote: "CLÁUSULA 3ª - O aluguel") ] }
    end

    def kept?(key, value)
      accepted(evidence_for(value, key)).candidates.any?
    end

    it "accepts ISO dates only, within a sane year range" do
      expect(kept?("signature_date", "2024-02-29")).to be(true)
      expect(kept?("signature_date", "2023-02-29")).to be(false)
      expect(kept?("signature_date", "29/02/2024")).to be(false)
      expect(kept?("signature_date", "1850-01-01")).to be(false)
    end

    it "accepts integers within each field's range, never floats or strings" do
      expect(kept?("rent_due_day", 31)).to be(true)
      expect(kept?("rent_due_day", 32)).to be(false)
      expect(kept?("rent_due_day", 5.0)).to be(false)
      expect(kept?("term_months", "60")).to be(false)
      expect(kept?("termination_notice_days", 0)).to be(true)
    end

    it "accepts money only as a decimal string with an ISO currency — never a number" do
      expect(kept?("monthly_rent", { "amount" => "12000", "currency" => "BRL" })).to be(true)
      expect(kept?("monthly_rent", { "amount" => "12000.5", "currency" => "BRL" })).to be(true)
      expect(kept?("monthly_rent", { "amount" => 12000.5, "currency" => "BRL" })).to be(false)
      expect(kept?("monthly_rent", { "amount" => "12.000,50", "currency" => "BRL" })).to be(false)
      expect(kept?("monthly_rent", { "amount" => "1.234", "currency" => "BRL" })).to be(false)
      expect(kept?("monthly_rent", { "amount" => "-10.00", "currency" => "BRL" })).to be(false)
      expect(kept?("monthly_rent", { "amount" => "10.00", "currency" => "reais" })).to be(false)
    end

    it "keeps the decimal exact" do
      attributes = accepted(evidence_for({ "amount" => "9999999999999.99", "currency" => "BRL" }, "monthly_rent"))
        .candidates.sole.attributes

      expect(attributes[:value_amount]).to eq(BigDecimal("9999999999999.99"))
    end

    it "accepts only the catalog's options" do
      expect(kept?("guarantee_type", "surety_insurance")).to be(true)
      expect(kept?("guarantee_type", "fianca")).to be(false)
    end

    it "trims text and rejects empty or overlong text" do
      expect(accepted(evidence_for("  Renovação automática.  ", "renewal_terms")).candidates.sole.attributes)
        .to eq(value_text: "Renovação automática.")
      expect(kept?("renewal_terms", "   ")).to be(false)
      expect(kept?("renewal_terms", "x" * 1_001)).to be(false)
    end

    it "accepts a party with or without a CPF/CNPJ, keeping digits only" do
      expect(accepted(evidence_for({ "name" => "Imobiliária Alfa Ltda.", "tax_id" => "12.345.678/0001-90" }, "lessor"))
        .candidates.sole.attributes).to eq(value_text: "Imobiliária Alfa Ltda.", value_tax_id: "12345678000190")
      expect(accepted(evidence_for({ "name" => "João", "tax_id" => nil }, "lessee")).candidates.sole.attributes)
        .to eq(value_text: "João", value_tax_id: nil)
      expect(kept?("lessee", { "name" => "João", "tax_id" => "123" })).to be(false)
      expect(kept?("lessee", { "name" => "", "tax_id" => nil })).to be(false)
    end
  end

  it "keeps several candidates for one field up to its cap and counts the rest as rejected" do
    quote = "CLÁUSULA 3ª"
    validated = accepted("rent_due_day" => (1..5).map { |day| candidate(day, page: 1, quote: quote) })

    expect(validated.candidates.map { |c| c.attributes[:value_integer] }).to eq([ 1, 2, 3 ])
    expect(validated.rejected_count).to eq(2)
  end

  it "returns candidates in catalog order, whatever the order of the answer" do
    output = { "lessor" => [ candidate({ "name" => "Alfa", "tax_id" => nil }, page: 1, quote: "Locador") ],
      "signature_date" => [ candidate("2024-01-10", page: 1, quote: "CLÁUSULA 3ª") ] }

    keys = described_class.call(output: FieldExtractionHelpers.empty_output.merge(output), pages: pages)
      .value.candidates.map(&:key)

    expect(keys).to eq(%w[signature_date lessor])
  end

  it "counts candidates under unknown keys as rejected" do
    result = described_class.call(output: output_with("favorite_color" => [ candidate("blue", page: 1, quote: "CLÁUSULA") ]),
      pages: pages)

    expect(result.value).to have_attributes(candidates: [], rejected_count: 1)
  end

  it "fails with invalid_output when the answer does not have the schema's shape" do
    expect(described_class.call(output: { "monthly_rent" => "12000" }, pages: pages).error).to eq("invalid_output")
    expect(described_class.call(output: [], pages: pages).error).to eq("invalid_output")
  end
end
