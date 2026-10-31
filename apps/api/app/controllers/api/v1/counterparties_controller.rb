module Api
  module V1
    # All actions require the X-Tenant-Id header (TenantScoped); a
    # counterparty of another tenant is a 404, exactly like a nonexistent one.
    #
    # GET   /api/v1/counterparties?status=active|archived&kind=individual|company&q=<text>&page=&per_page=
    #   200 { data: [counterparty, ...], meta: { page, per_page, total_count, total_pages } }
    # GET   /api/v1/counterparties/:id
    #   200 { data: counterparty }
    # POST  /api/v1/counterparties  { counterparty: { kind, legal_name, trade_name, tax_id, email, phone } }
    #   201 { data: counterparty }  (owner/admin/manager; tax_id accepts CPF/CNPJ with or without punctuation)
    # PATCH /api/v1/counterparties/:id  { counterparty: { ...same fields, status } }
    #   200 { data: counterparty }  (owner/admin/manager; status "archived" archives it)
    #
    # counterparty = { id, kind, legal_name, trade_name, tax_id, email, phone, status,
    #   created_at, updated_at }
    # Errors: 400 invalid_parameter/parameter_missing, 401, 403 forbidden/tenant_forbidden,
    #   404 not_found, 422 validation_failed (with details).
    class CounterpartiesController < ApplicationController
      include TenantScoped
      include Paginated

      CREATE_ATTRIBUTES = %i[kind legal_name trade_name tax_id email phone].freeze

      def index
        authorize Counterparty
        relation = Portfolio::CounterpartiesQuery.call(
          policy_scope(Counterparty),
          status: permitted_filter(:status, Counterparty.statuses.keys),
          kind: permitted_filter(:kind, Counterparty.kinds.keys),
          search: text_filter(:q)
        )
        counterparties, meta = paginate(relation)

        render json: {
          data: counterparties.map { |counterparty| CounterpartySerializer.new(counterparty).as_json },
          meta: meta
        }
      end

      def show
        counterparty = policy_scope(Counterparty).find(params[:id])
        authorize counterparty

        render json: { data: CounterpartySerializer.new(counterparty).as_json }
      end

      def create
        authorize Counterparty
        result = Portfolio::CreateCounterparty.call(
          tenant: current_membership.tenant,
          attributes: params.require(:counterparty).permit(*CREATE_ATTRIBUTES)
        )

        if result.success?
          render json: { data: CounterpartySerializer.new(result.value).as_json }, status: :created
        else
          render_validation_errors(result.error)
        end
      end

      def update
        counterparty = policy_scope(Counterparty).find(params[:id])
        authorize counterparty
        result = Portfolio::UpdateCounterparty.call(
          counterparty: counterparty,
          attributes: params.require(:counterparty).permit(*CREATE_ATTRIBUTES, :status)
        )

        if result.success?
          render json: { data: CounterpartySerializer.new(result.value).as_json }
        else
          render_validation_errors(result.error)
        end
      end
    end
  end
end
