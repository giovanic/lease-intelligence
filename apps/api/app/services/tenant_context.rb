# Establishes the per-transaction PostgreSQL session settings that every
# RLS policy reads (app_current_tenant_id() / app_current_user_id(), see
# db/migrate/20261031133221_enable_tenancy_sql_functions.rb). This is the
# ONE place in the codebase that is allowed to set that context — request
# middleware and background jobs must go through here rather than issuing
# `SET` themselves, so the transaction-scoping guarantee stays in one
# place (docs/architecture/multi-tenancy.md "connection pool safety").
#
# `SET LOCAL` (here via `set_config(..., true)`, its parameterized
# equivalent) only lives for the current transaction — it cannot leak
# onto a pooled connection reused by a later, unrelated request or job.
#
# Two details that are easy to get wrong here and matter for correctness:
#
# 1. `ActiveRecord::Base.transaction do ... end`, called while already
#    inside an open transaction (e.g. a broader request-level transaction,
#    or a test suite's transactional-fixtures wrapper), does NOT open a
#    new sub-transaction unless `requires_new: true` is passed — without
#    it, a `SET LOCAL` done "inside" is really scoped to the *enclosing*
#    transaction, and an error raised inside is NOT contained to a
#    rollback-able boundary, it poisons the whole enclosing transaction.
#    `requires_new: true` forces a real SAVEPOINT, so both of those are
#    bounded to this call.
# 2. PostgreSQL's rule for a `SET LOCAL` done inside a subtransaction that
#    then *successfully completes* (the savepoint is released, not rolled
#    back) is that the setting persists into the enclosing transaction —
#    it is not automatically reverted just because our block returned.
#    So activation is explicitly undone in `ensure`, not left to transaction
#    boundaries alone; this is what actually prevents context from
#    bleeding into unrelated code that runs later in the same enclosing
#    transaction.
class TenantContext
  class << self
    # Runs the block with the given tenant/user set as the RLS context
    # for the duration of one transaction. Pass `user:` alone (no tenant)
    # to support the "which organizations am I in" bootstrap query, which
    # relies on memberships' self-visibility policy rather than tenant
    # isolation.
    def activate(tenant: nil, user: nil)
      raise ArgumentError, "TenantContext.activate requires a block" unless block_given?

      ActiveRecord::Base.transaction(requires_new: true) do
        set_local("app.current_tenant_id", tenant&.id)
        set_local("app.current_user_id", user&.id)
        Current.tenant = tenant
        Current.user = user
        yield
      end
    ensure
      set_local("app.current_tenant_id", nil)
      set_local("app.current_user_id", nil)
      Current.tenant = nil
      Current.user = nil
    end

    private

    def set_local(setting, value)
      ActiveRecord::Base.connection.select_value(
        "SELECT set_config(#{ActiveRecord::Base.connection.quote(setting)}, #{ActiveRecord::Base.connection.quote(value.to_s)}, true)"
      )
    end
  end
end
