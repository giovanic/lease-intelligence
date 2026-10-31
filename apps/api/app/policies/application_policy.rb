# frozen_string_literal: true

# Deny-by-default base policy (docs/architecture/security.md). Pundit's
# "user" here is an AuthorizationContext, not a bare User: role decisions
# inside a tenant come from the *membership* resolved server-side by
# TenantScoped (docs/adr/0013-spa-session-auth-and-tenant-selection.md),
# never from client input. `membership` is nil on endpoints that are not
# tenant-scoped (e.g. GET /api/v1/me).
class ApplicationPolicy
  attr_reader :context, :record

  delegate :user, :membership, to: :context

  def initialize(context, record)
    raise Pundit::NotAuthorizedError, "must be authenticated" unless context&.user

    @context = context
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(context, scope)
      @context = context
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :context, :scope
  end
end
