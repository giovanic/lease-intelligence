# Offset pagination for collection endpoints (.claude/rules/api.md: no
# unbounded arrays). Plain limit/offset, no gem: collections are per
# tenant and ordered by a stable key, which is enough at this stage.
#
#   ?page=2&per_page=50
#   => { data: [...], meta: { page: 2, per_page: 50, total_count: 120, total_pages: 3 } }
#
# Non-integer or out-of-range values are rejected with 400, not silently
# clamped, so a client bug is visible.
module Paginated
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  private

  # Returns [records, meta] for an already ordered relation.
  def paginate(relation)
    page = pagination_param(:page, default: 1, max: nil)
    per_page = pagination_param(:per_page, default: DEFAULT_PER_PAGE, max: MAX_PER_PAGE)
    total_count = relation.count

    records = relation.limit(per_page).offset((page - 1) * per_page).to_a
    meta = { page: page, per_page: per_page, total_count: total_count, total_pages: (total_count.to_f / per_page).ceil }
    [ records, meta ]
  end

  def pagination_param(name, default:, max:)
    raw = params[name]
    return default if raw.blank?

    value = Integer(raw.to_s, 10, exception: false)
    if value.nil? || value < 1 || (max && value > max)
      range = max ? "between 1 and #{max}" : "a positive integer"
      raise ApplicationController::InvalidQueryParameter, "#{name} must be #{range}."
    end
    value
  end
end
