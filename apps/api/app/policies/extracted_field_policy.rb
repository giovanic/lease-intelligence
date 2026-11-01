# frozen_string_literal: true

# Extracted fields are reached only to decide on them (ReviewDecisionPolicy)
# or through their run (ExtractionRunPolicy). This policy exists for its
# Scope (the tenant's own rows, on top of RLS); every action is denied.
class ExtractedFieldPolicy < TenantOwnedPolicy
end
