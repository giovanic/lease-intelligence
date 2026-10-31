module Api
  module V1
    # All actions require the X-Tenant-Id header (TenantScoped); a property
    # of another tenant is a 404, exactly like a nonexistent one.
    #
    # GET   /api/v1/properties?status=active|archived&q=<text>&page=&per_page=
    #   200 { data: [property, ...], meta: { page, per_page, total_count, total_pages } }
    # GET   /api/v1/properties/:id
    #   200 { data: property }
    # POST  /api/v1/properties   { property: { name, code, property_type, street, number,
    #                              complement, district, city, state, postal_code,
    #                              country_code, area_sqm } }
    #   201 { data: property }   (owner/admin/manager)
    # PATCH /api/v1/properties/:id  { property: { ...same fields, status } }
    #   200 { data: property }   (owner/admin/manager; status "archived" archives it)
    #
    # property = { id, name, code, property_type, status, address: { street, number,
    #   complement, district, city, state, postal_code, country_code }, area_sqm,
    #   created_at, updated_at }
    # Errors: 400 invalid_parameter/parameter_missing, 401, 403 forbidden/tenant_forbidden,
    #   404 not_found, 422 validation_failed (with details).
    class PropertiesController < ApplicationController
      include TenantScoped
      include Paginated

      CREATE_ATTRIBUTES = %i[
        name code property_type street number complement district city state postal_code
        country_code area_sqm
      ].freeze

      def index
        authorize Property
        relation = Portfolio::PropertiesQuery.call(
          policy_scope(Property),
          status: permitted_filter(:status, Property.statuses.keys),
          search: text_filter(:q)
        )
        properties, meta = paginate(relation)

        render json: { data: properties.map { |property| PropertySerializer.new(property).as_json }, meta: meta }
      end

      def show
        property = policy_scope(Property).find(params[:id])
        authorize property

        render json: { data: PropertySerializer.new(property).as_json }
      end

      def create
        authorize Property
        result = Portfolio::CreateProperty.call(
          tenant: current_membership.tenant,
          attributes: params.require(:property).permit(*CREATE_ATTRIBUTES)
        )

        if result.success?
          render json: { data: PropertySerializer.new(result.value).as_json }, status: :created
        else
          render_validation_errors(result.error)
        end
      end

      def update
        property = policy_scope(Property).find(params[:id])
        authorize property
        result = Portfolio::UpdateProperty.call(
          property: property,
          attributes: params.require(:property).permit(*CREATE_ATTRIBUTES, :status)
        )

        if result.success?
          render json: { data: PropertySerializer.new(result.value).as_json }
        else
          render_validation_errors(result.error)
        end
      end
    end
  end
end
