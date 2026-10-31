module Api
  module V1
    # GET /api/v1/me
    #   200 { data: { user: {id, email, full_name}, memberships: [...] } }
    #   401 when not signed in
    # Not tenant-scoped: this is how the SPA learns which organizations the
    # user can select before sending any X-Tenant-Id.
    class MeController < ApplicationController
      before_action :authenticate_user!

      def show
        authorize current_user
        render json: { data: MeSerializer.new(current_user).as_json }
      end
    end
  end
end
