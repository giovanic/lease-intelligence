# frozen_string_literal: true

# Any active member of the tenant reads the portfolio; owners, admins and
# managers register and edit it. There is no destroy: properties are
# archived (status), because leases will reference them.
class PropertyPolicy < TenantOwnedPolicy
  def index?
    member_of_record_tenant?
  end

  def show?
    member_of_record_tenant?
  end

  def create?
    role_in?(EDITOR_ROLES)
  end

  def update?
    role_in?(EDITOR_ROLES)
  end
end
