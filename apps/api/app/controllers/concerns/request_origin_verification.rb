# CSRF protection for cookie-authenticated, state-changing requests
# (docs/adr/0013-spa-session-auth-and-tenant-selection.md). Works together
# with the SameSite=Lax session cookie; Rails' form-token CSRF is not used
# because there are no server-rendered forms.
#
# - A request whose `Origin` is neither the API's own origin nor an
#   explicitly configured extra origin is rejected — the same check Rails'
#   forgery protection does (`request.origin == request.base_url`).
# - `Sec-Fetch-Site: cross-site` is rejected even without an Origin.
# - A request body must be JSON: a cross-site HTML form cannot send
#   `application/json` without a CORS preflight, which this API never grants.
module RequestOriginVerification
  extend ActiveSupport::Concern

  SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

  included do
    before_action :verify_request_origin
  end

  private

  def verify_request_origin
    return if SAFE_METHODS.include?(request.request_method)

    if cross_site_request?
      render_error(:forbidden, "cross_site_request", "Cross-site requests are not allowed.")
    elsif request.content_length.to_i.positive? && request.media_type != "application/json"
      render_error(:unsupported_media_type, "unsupported_media_type", "Request body must be application/json.")
    end
  end

  def cross_site_request?
    origin = request.origin
    return true if origin.present? && !allowed_origin?(origin)

    request.headers["Sec-Fetch-Site"] == "cross-site"
  end

  def allowed_origin?(origin)
    origin == request.base_url || Rails.configuration.x.extra_allowed_origins.include?(origin)
  end
end
