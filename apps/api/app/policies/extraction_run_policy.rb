# frozen_string_literal: true

# AI field extraction runs (docs/adr/0017). Reading a run — its candidate
# fields and the quoted evidence — is open to any active member of the
# tenant: the same audience that can already download the file
# (DocumentVersionPolicy#show?). Requesting a new run, which costs a
# provider call, is for the roles that upload files.
class ExtractionRunPolicy < TenantOwnedPolicy
  def show?
    member_of_record_tenant?
  end

  def create?
    role_in?(EDITOR_ROLES)
  end
end
