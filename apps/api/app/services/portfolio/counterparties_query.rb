module Portfolio
  # Filters and orders an already tenant-scoped Counterparty relation for
  # GET /api/v1/counterparties. `search` matches legal/trade name
  # (case-insensitive substring) or, when it contains digits, the tax id
  # with punctuation ignored ("12.345.678/0001-95" finds 12345678000195).
  class CounterpartiesQuery
    def self.call(relation, status: nil, kind: nil, search: nil)
      relation = relation.where(status: status) if status
      relation = relation.where(kind: kind) if kind
      relation = relation.where(search_condition(search)) if search.present?
      relation.order(:legal_name, :id)
    end

    def self.search_condition(search)
      table = Counterparty.arel_table
      term = "%#{Counterparty.sanitize_sql_like(search.strip)}%"
      condition = table[:legal_name].matches(term).or(table[:trade_name].matches(term))

      digits = search.gsub(/\D/, "")
      return condition if digits.empty?

      # A pre-quoted node: a plain string would be type-cast through the
      # attribute, and `normalizes :tax_id` would strip the % wildcards.
      condition.or(table[:tax_id].matches(Arel::Nodes::Quoted.new("%#{digits}%")))
    end
    private_class_method :search_condition
  end
end
