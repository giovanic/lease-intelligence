# frozen_string_literal: true

# Requesting a new text extraction of a version (docs/adr/0016) is for the
# roles that upload files — owners, admins and managers. Every member sees
# an extraction's status through the version it belongs to
# (DocumentVersionPolicy#show?); the extracted text itself is not exposed
# by the API yet.
class DocumentTextExtractionPolicy < TenantOwnedPolicy
  def create?
    role_in?(EDITOR_ROLES)
  end
end
