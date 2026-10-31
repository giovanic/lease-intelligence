module RequestHelpers
  def json
    JSON.parse(response.body)
  end

  # Signs in through the real endpoint so the session cookie is kept by
  # the integration session for the following requests.
  def sign_in_as(user, password: "password123!")
    post "/api/v1/session", params: { email: user.email, password: password }, as: :json
    expect(response).to have_http_status(:created)
  end

  def current_db_setting(name)
    ActiveRecord::Base.connection.select_value("SELECT current_setting(#{ActiveRecord::Base.connection.quote(name)}, true)")
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
