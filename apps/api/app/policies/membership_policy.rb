# frozen_string_literal: true

class MembershipPolicy < ApplicationPolicy
  # Only the caller's own active membership in the current tenant is
  # readable through GET /api/v1/current_membership. Listing other members
  # is a separate, role-gated permission not built in this phase.
  def show?
    membership.present? &&
      record == membership &&
      record.user_id == user.id &&
      record.active?
  end
end
