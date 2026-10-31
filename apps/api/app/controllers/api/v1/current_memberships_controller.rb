module Api
  module V1
    # GET /api/v1/current_membership   (header X-Tenant-Id: <tenant uuid>)
    #   200 { data: { id, role, status, tenant: {id, name, slug} } }
    #   400 tenant_required  — header missing
    #   401 unauthenticated
    #   403 tenant_forbidden — not an active member of an active tenant
    # Lets the SPA confirm a tenant selection and read the user's role in it.
    class CurrentMembershipsController < ApplicationController
      include TenantScoped

      def show
        authorize current_membership
        render json: { data: MembershipSerializer.new(current_membership).as_json }
      end
    end
  end
end
