# frozen_string_literal: true

# Deciding on AI-extracted fields (docs/adr/0019) is for the roles that
# check contracts: owners, admins, managers and analysts. Viewers read the
# decisions through the run (ExtractionRunPolicy#show?). Decisions are
# append-only: there is no update or destroy.
class ReviewDecisionPolicy < TenantOwnedPolicy
  REVIEWER_ROLES = %w[owner admin manager analyst].freeze

  def create?
    role_in?(REVIEWER_ROLES)
  end
end
