require "rails_helper"

RSpec.describe BrazilianTaxId do
  describe ".valid_cpf?" do
    it "accepts a CPF with correct check digits" do
      expect(described_class.valid_cpf?("52998224725")).to be(true)
    end

    it "rejects a wrong check digit" do
      expect(described_class.valid_cpf?("52998224724")).to be(false)
    end

    it "rejects repeated-digit sequences, which pass the arithmetic" do
      expect(described_class.valid_cpf?("11111111111")).to be(false)
    end

    it "rejects non-normalized or wrong-length input" do
      expect(described_class.valid_cpf?("529.982.247-25")).to be(false)
      expect(described_class.valid_cpf?("5299822472")).to be(false)
      expect(described_class.valid_cpf?(nil)).to be(false)
    end
  end

  describe ".valid_cnpj?" do
    it "accepts a CNPJ with correct check digits" do
      expect(described_class.valid_cnpj?("11222333000181")).to be(true)
    end

    it "rejects a wrong check digit" do
      expect(described_class.valid_cnpj?("11222333000180")).to be(false)
    end

    it "rejects repeated-digit sequences and wrong-length input" do
      expect(described_class.valid_cnpj?("00000000000000")).to be(false)
      expect(described_class.valid_cnpj?("52998224725")).to be(false)
    end
  end

  it "agrees with the spec generator used by the factories" do
    expect(described_class.valid_cpf?(BrazilianTaxIdGenerator.cpf(42))).to be(true)
    expect(described_class.valid_cnpj?(BrazilianTaxIdGenerator.cnpj(42))).to be(true)
  end
end
