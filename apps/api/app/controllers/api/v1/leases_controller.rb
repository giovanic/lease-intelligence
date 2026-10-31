module Api
  module V1
    # All actions require the X-Tenant-Id header (TenantScoped); a lease of
    # another tenant is a 404, exactly like a nonexistent one.
    #
    # GET   /api/v1/leases?status=draft|active|expired|terminated&property_id=<uuid>
    #                     &counterparty_id=<uuid>&q=<text>&page=&per_page=
    #   200 { data: [lease, ...], meta: { page, per_page, total_count, total_pages } }
    # GET   /api/v1/leases/:id
    #   200 { data: lease }
    # POST  /api/v1/leases   { lease: { title, code, notes, status, property_id,
    #                          parties: [{ counterparty_id, role }] } }
    #   201 { data: lease }   (owner/admin/manager; at least one "lessor" party)
    # PATCH /api/v1/leases/:id  { lease: { ...same fields } }
    #   200 { data: lease }   (owner/admin/manager; `parties`, when given, replaces
    #                          the list; property_id only changes while "draft")
    #
    # lease = { id, title, code, status, notes,
    #   property: { id, name, code, city, state },
    #   parties: [{ id, role: lessor|guarantor|intervening_party,
    #               counterparty: { id, kind, legal_name, trade_name } }],
    #   created_at, updated_at }
    # Errors: 400 invalid_parameter/parameter_missing, 401, 403 forbidden/tenant_forbidden,
    #   404 not_found, 422 validation_failed (with details; a property/counterparty
    #   id of another tenant is "not found", e.g. "parties[0].counterparty_id").
    class LeasesController < ApplicationController
      include TenantScoped
      include Paginated

      UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def index
        authorize Lease
        relation = Leases::LeasesQuery.call(
          policy_scope(Lease),
          status: permitted_filter(:status, Lease.statuses.keys),
          property_id: uuid_filter(:property_id),
          counterparty_id: uuid_filter(:counterparty_id),
          search: text_filter(:q)
        )
        leases, meta = paginate(relation)

        render json: { data: leases.map { |lease| LeaseSerializer.new(lease).as_json }, meta: meta }
      end

      def show
        lease = find_lease
        authorize lease

        render json: { data: LeaseSerializer.new(lease).as_json }
      end

      def create
        authorize Lease
        result = Leases::CreateLease.call(tenant: current_membership.tenant, attributes: lease_params)

        if result.success?
          render json: { data: LeaseSerializer.new(result.value).as_json }, status: :created
        else
          render_validation_errors(result.error)
        end
      end

      def update
        lease = find_lease
        authorize lease
        result = Leases::UpdateLease.call(lease: lease, attributes: lease_params)

        if result.success?
          render json: { data: LeaseSerializer.new(result.value).as_json }
        else
          render_validation_errors(result.error)
        end
      end

      private

      def find_lease
        policy_scope(Lease).includes(:property, lease_parties: :counterparty).find(params[:id])
      end

      def lease_params
        params.require(:lease).permit(:title, :code, :notes, :status, :property_id, parties: %i[counterparty_id role])
      end

      def uuid_filter(name)
        value = text_filter(name)
        return if value.nil?
        raise InvalidQueryParameter, "#{name} must be a UUID." unless value.match?(UUID_FORMAT)

        value
      end
    end
  end
end
