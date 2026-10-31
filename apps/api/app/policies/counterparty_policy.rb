# frozen_string_literal: true

# Same matrix as PropertyPolicy: any active member reads; owners, admins
# and managers register and edit. No destroy — counterparties are archived.
class CounterpartyPolicy < TenantOwnedPolicy
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
