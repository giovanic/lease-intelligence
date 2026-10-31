# Request/job-local, Ruby-side convenience accessor for "who is acting and
# as which tenant" (docs/architecture/multi-tenancy.md). This is NOT the
# enforcement mechanism — PostgreSQL RLS is (docs/adr/0003-postgresql-rls.md).
# Current is reset automatically by Rails between requests/jobs; the actual
# database-level tenant context is set and cleared per-transaction by
# TenantContext, independently of this class.
class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :user
end
