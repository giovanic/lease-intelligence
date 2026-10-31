# frozen_string_literal: true

# Base for policies over tenant-owned records (anything with tenant_id).
# Every permission requires an active membership in the record's tenant;
# subclasses then decide which roles may do what. This is defense in depth
# on top of RLS (docs/adr/0003-postgresql-rls.md) — RLS already hides other
# tenants' rows, the policy must still never grant access to one.
class TenantOwnedPolicy < ApplicationPolicy
  # Roles allowed to register and edit portfolio-style records
  # (docs/product/workflows.md: "Admin/manager registers ...").
  EDITOR_ROLES = %w[owner admin manager].freeze

  private

  def member_of_record_tenant?
    membership.present? &&
      membership.active? &&
      membership.user_id == user.id &&
      record_tenant_id.present? &&
      membership.tenant_id == record_tenant_id
  end

  def role_in?(roles)
    member_of_record_tenant? && roles.include?(membership.role)
  end

  # `record` is an instance for show/update, or the model class for
  # index/create (where the target tenant is the current one).
  def record_tenant_id
    record.is_a?(Class) ? membership&.tenant_id : record.tenant_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      membership = context.membership
      return scope.none unless membership&.active? && membership.user_id == context.user&.id

      scope.where(tenant_id: membership.tenant_id)
    end
  end
end
