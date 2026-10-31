# Builds check-digit-valid CPF/CNPJ numbers for factories and specs, so
# sequences never collide with the uniqueness index and never trip the
# model's check-digit validation by accident.
module BrazilianTaxIdGenerator
  module_function

  def cpf(seed)
    base = format("%09d", seed % 1_000_000_000).chars.map(&:to_i)
    base = [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ] if base.uniq.size == 1
    first = cpf_digit(base, 10)
    (base + [ first, cpf_digit(base + [ first ], 11) ]).join
  end

  def cnpj(seed)
    base = format("%08d", seed % 100_000_000).chars.map(&:to_i) + [ 0, 0, 0, 1 ]
    first = cnpj_digit(base, BrazilianTaxId::CNPJ_FIRST_WEIGHTS)
    (base + [ first, cnpj_digit(base + [ first ], BrazilianTaxId::CNPJ_SECOND_WEIGHTS) ]).join
  end

  def cpf_digit(digits, start_weight)
    remainder = (digits.each_with_index.sum { |digit, index| digit * (start_weight - index) } * 10) % 11
    remainder == 10 ? 0 : remainder
  end

  def cnpj_digit(digits, weights)
    remainder = digits.zip(weights).sum { |digit, weight| digit * weight } % 11
    remainder < 2 ? 0 : 11 - remainder
  end
end
