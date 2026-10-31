module Api
  module V1
    # POST   /api/v1/session  { "email": "...", "password": "..." }
    #   201 { data: { user: {id, email, full_name}, memberships: [...] } } + session cookie
    #   401 { error: { code: "invalid_credentials" } } — same for every failure
    # DELETE /api/v1/session  204, session reset
    class SessionsController < ApplicationController
      before_action :authenticate_user!, only: :destroy

      def create
        # Unauthenticated endpoint: there is no resource or user to
        # authorize yet; abuse is limited by Rack::Attack instead.
        skip_authorization

        result = Identity::AuthenticateUser.call(
          email: params.require(:email),
          password: params.require(:password)
        )

        if result.success?
          sign_in(:user, result.value)
          render json: { data: MeSerializer.new(result.value).as_json }, status: :created
        else
          render_error(:unauthorized, "invalid_credentials", "Invalid email or password.")
        end
      end

      def destroy
        # Ending one's own session needs no permission beyond being signed in.
        skip_authorization
        sign_out
        head :no_content
      end
    end
  end
end
