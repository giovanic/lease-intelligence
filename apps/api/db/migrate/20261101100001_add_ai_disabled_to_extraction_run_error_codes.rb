# A run queued while the organization had AI extraction on, and started
# after it was turned off, fails with `ai_disabled` before any provider
# call (docs/adr/0018).
class AddAiDisabledToExtractionRunErrorCodes < ActiveRecord::Migration[8.1]
  OLD_CODES = %w[rate_limited provider_unavailable timeout output_truncated refused invalid_output text_too_long
    abandoned internal_error].freeze
  NEW_CODES = (OLD_CODES + %w[ai_disabled]).freeze

  def up
    replace_constraint(NEW_CODES)
  end

  def down
    replace_constraint(OLD_CODES)
  end

  private

  def replace_constraint(codes)
    remove_check_constraint :extraction_runs, name: "extraction_runs_error_code_check"
    add_check_constraint :extraction_runs,
      "error_code IS NULL OR error_code IN (#{codes.map { |code| connection.quote(code) }.join(", ")})",
      name: "extraction_runs_error_code_check"
  end
end
