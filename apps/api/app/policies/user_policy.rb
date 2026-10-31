# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  # A user may only read their own profile (GET /api/v1/me).
  def show?
    record == user
  end
end
