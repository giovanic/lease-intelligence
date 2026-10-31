# Check-digit validation for Brazilian taxpayer ids (CPF for individuals,
# CNPJ for legal entities). Input must already be digits only — callers
# normalize first. Repeated-digit sequences (000.000.000-00, ...) pass the
# arithmetic but are not issued, so they are rejected explicitly.
module BrazilianTaxId
  CPF_LENGTH = 11
  CNPJ_LENGTH = 14
  CNPJ_FIRST_WEIGHTS = [ 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
  CNPJ_SECOND_WEIGHTS = [ 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze

  module_function

  def valid_cpf?(value)
    digits = digits_of(value, CPF_LENGTH)
    return false unless digits

    first = cpf_check_digit(digits.first(9), 10)
    second = cpf_check_digit(digits.first(9) + [ first ], 11)
    digits[9] == first && digits[10] == second
  end

  def valid_cnpj?(value)
    digits = digits_of(value, CNPJ_LENGTH)
    return false unless digits

    first = cnpj_check_digit(digits.first(12), CNPJ_FIRST_WEIGHTS)
    second = cnpj_check_digit(digits.first(12) + [ first ], CNPJ_SECOND_WEIGHTS)
    digits[12] == first && digits[13] == second
  end

  def digits_of(value, length)
    return unless value.is_a?(String) && value.match?(/\A\d{#{length}}\z/)

    digits = value.chars.map(&:to_i)
    digits.uniq.size == 1 ? nil : digits
  end

  def cpf_check_digit(digits, start_weight)
    sum = digits.each_with_index.sum { |digit, index| digit * (start_weight - index) }
    remainder = (sum * 10) % 11
    remainder == 10 ? 0 : remainder
  end

  def cnpj_check_digit(digits, weights)
    remainder = digits.zip(weights).sum { |digit, weight| digit * weight } % 11
    remainder < 2 ? 0 : 11 - remainder
  end

  private_class_method :digits_of, :cpf_check_digit, :cnpj_check_digit
end
