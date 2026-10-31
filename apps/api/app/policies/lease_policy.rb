# frozen_string_literal: true

# Same matrix as the portfolio: any active member of the tenant reads
# leases; owners, admins and managers register and edit them
# (docs/product/workflows.md: "Manager creates a Lease"). There is no
# destroy: a lease ends through its status (expired/terminated), and its
# documents and conditions will reference it.
class LeasePolicy < TenantOwnedPolicy
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
