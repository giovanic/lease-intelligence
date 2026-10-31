module Portfolio
  # Filters and orders an already tenant-scoped Property relation for
  # GET /api/v1/properties. `search` matches name, code or city
  # (case-insensitive substring); LIKE wildcards in it are escaped.
  class PropertiesQuery
    def self.call(relation, status: nil, search: nil)
      relation = relation.where(status: status) if status
      if search.present?
        term = "%#{Property.sanitize_sql_like(search.strip)}%"
        relation = relation.where(
          "properties.name ILIKE :term OR properties.code ILIKE :term OR properties.city ILIKE :term", term: term
        )
      end
      relation.order(:name, :id)
    end
  end
end
