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
#   The one exception is an action declared with `accepts_multipart_body`
#   (file uploads) on a TenantScoped controller: those also require the
#   X-Tenant-Id header, which a cross-site form cannot set without the same
#   preflight — so the guarantee holds.
module RequestOriginVerification
  extend ActiveSupport::Concern

  SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

  included do
    before_action :verify_request_origin
    class_attribute :multipart_body_actions, instance_writer: false, default: [].freeze
  end

  class_methods do
    def accepts_multipart_body(*actions)
      unless include?(TenantScoped)
        raise ArgumentError, "multipart bodies are only accepted on TenantScoped controllers (custom-header CSRF guard)"
      end

      self.multipart_body_actions = (multipart_body_actions + actions.map(&:to_s)).freeze
    end
  end

  private

  def verify_request_origin
    return if SAFE_METHODS.include?(request.request_method)

    if cross_site_request?
      render_error(:forbidden, "cross_site_request", "Cross-site requests are not allowed.")
    elsif request.content_length.to_i.positive? && !accepted_body_media_type?
      render_error(:unsupported_media_type, "unsupported_media_type", "Request body must be application/json.")
    end
  end

  def accepted_body_media_type?
    request.media_type == "application/json" ||
      (request.media_type == "multipart/form-data" && multipart_body_actions.include?(action_name))
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
