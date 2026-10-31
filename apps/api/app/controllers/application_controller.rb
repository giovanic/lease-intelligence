class ApplicationController < ActionController::API
  include Pundit::Authorization
  include RequestOriginVerification

  # Every action must call `authorize` (or explicitly `skip_authorization`
  # with a reason) — deny by default (docs/architecture/security.md).
  after_action :verify_authorized

  rescue_from Pundit::NotAuthorizedError do
    render_error(:forbidden, "forbidden", "You are not allowed to perform this action.")
  end

  rescue_from ActionController::ParameterMissing do |error|
    render_error(:bad_request, "parameter_missing", error.message)
  end

  private

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
