# frozen_string_literal: true

# Settings of the current organization (docs/adr/0018). `record` is the
# Tenant TenantScoped resolved; `tenants` has no RLS, so this policy is the
# check that the caller is an active member of exactly that tenant. Any
# active member reads (the documents screen needs to know whether AI
# extraction is on); only owners and admins change them — turning AI
# extraction on is a decision to send the organization's contracts to it.
class OrganizationSettingsPolicy < ApplicationPolicy
  MANAGER_ROLES = %w[owner admin].freeze

  def show?
    member_of_record?
  end

  def update?
    member_of_record? && MANAGER_ROLES.include?(membership.role)
  end

  private

  def member_of_record?
    record.is_a?(Tenant) &&
      membership.present? &&
      membership.active? &&
      membership.user_id == user&.id &&
      membership.tenant_id == record.id
  end
end
