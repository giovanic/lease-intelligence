# Explicit JSON shape for a Counterparty. tax_id (CPF/CNPJ) is returned
# to authorized members of the owning tenant only — it is never logged
# (filter_parameter_logging.rb).
class CounterpartySerializer
  def initialize(counterparty)
    @counterparty = counterparty
  end

  def as_json(*)
    {
      id: @counterparty.id,
      kind: @counterparty.kind,
      legal_name: @counterparty.legal_name,
      trade_name: @counterparty.trade_name,
      tax_id: @counterparty.tax_id,
      email: @counterparty.email,
      phone: @counterparty.phone,
      status: @counterparty.status,
      created_at: @counterparty.created_at,
      updated_at: @counterparty.updated_at
    }
  end
end
