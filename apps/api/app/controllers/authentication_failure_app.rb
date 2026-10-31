# Warden failure app (wired in config/initializers/devise.rb): answers
# every failed authentication — missing session, idle timeout — with a 401
# in the API's standard error envelope instead of Devise's default body.
class AuthenticationFailureApp < Devise::FailureApp
  def respond
    self.status = :unauthorized
    self.content_type = "application/json"
    self.response_body = {
      error: { code: "unauthenticated", message: i18n_message }
    }.to_json
  end
end
