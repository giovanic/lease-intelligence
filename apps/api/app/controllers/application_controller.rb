class ApplicationController < ActionController::API
  include Pundit::Authorization
  include RequestOriginVerification

  # Every action must call `authorize` (or explicitly `skip_authorization`
  # with a reason) — deny by default (docs/architecture/security.md).
  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do
    render_error(:forbidden, "forbidden", "You are not allowed to perform this action.")
  end

  # A malformed query-string value (page, filter, ...) — 400, not ignored.
  class InvalidQueryParameter < StandardError; end

  rescue_from ActionController::ParameterMissing do |error|
    render_error(:bad_request, "parameter_missing", error.message)
  end

  rescue_from InvalidQueryParameter do |error|
    render_error(:bad_request, "invalid_parameter", error.message)
  end

  # Also what a record of another tenant looks like: RLS hides the row,
  # so it is indistinguishable from one that does not exist.
  rescue_from ActiveRecord::RecordNotFound do
    render_error(:not_found, "not_found", "Resource not found.")
  end

  private

  # Accepts only a known value for an optional query filter.
  def permitted_filter(name, allowed)
    value = params[name]
    return if value.blank?
    raise InvalidQueryParameter, "#{name} must be one of: #{allowed.join(', ')}." unless allowed.include?(value)

    value
  end

  # An optional free-text query param; rejects arrays/hashes (?q[]=...).
  def text_filter(name)
    value = params[name]
    return if value.blank?
    raise InvalidQueryParameter, "#{name} must be a string." unless value.is_a?(String)

    value
  end

  # 422 with per-field messages: { error: { code, message, details: { field: [...] } } }.
  def render_validation_errors(errors)
    render json: {
      error: { code: "validation_failed", message: "Validation failed.", details: errors.to_hash }
    }, status: :unprocessable_content
  end

  def pundit_user
    AuthorizationContext.new(user: current_user, membership: current_membership)
  end

  # Overridden by TenantScoped on tenant-scoped controllers.
  def current_membership
    nil
  end

  # Single error envelope for the whole API: { error: { code, message } }.
  def render_error(status, code, message)
    render json: { error: { code: code, message: message } }, status: status
  end
end
