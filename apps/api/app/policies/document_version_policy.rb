# frozen_string_literal: true

# Reading a version — including receiving its bytes through a download
# link (docs/adr/0015) — is open to any active member of the tenant;
# uploading a new version is for owners, admins and managers. Versions are
# immutable: there is no update or destroy.
class DocumentVersionPolicy < TenantOwnedPolicy
  def show?
    member_of_record_tenant?
  end

  def create?
    role_in?(EDITOR_ROLES)
  end
end
