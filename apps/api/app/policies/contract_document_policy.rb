# frozen_string_literal: true

# Same matrix as leases: any active member of the tenant lists and reads a
# lease's documents; owners, admins and managers upload them
# (docs/product/workflows.md: "Manager uploads the signed contract"). There
# is no update or destroy: the files are immutable versions and the
# document is referenced by them.
class ContractDocumentPolicy < TenantOwnedPolicy
  def index?
    member_of_record_tenant?
  end

  def show?
    member_of_record_tenant?
  end

  def create?
    role_in?(EDITOR_ROLES)
  end
end
