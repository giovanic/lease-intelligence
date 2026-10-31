# Shared helpers used by every Row-Level Security policy in the system
# (docs/architecture/multi-tenancy.md, docs/adr/0003-postgresql-rls.md).
#
# The application sets two per-transaction session settings via
# TenantContext.activate: `app.current_tenant_id` (standard tenant
# isolation) and `app.current_user_id` (lets a user see their own
# memberships across tenants, needed to bootstrap "which orgs am I in"
# before a tenant is selected). Both are read through these functions so
# every RLS policy in every future migration uses the same, safe
# NULL-handling instead of repeating `NULLIF(current_setting(...), '')`
# boilerplate on every table.
class EnableTenancySqlFunctions < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE FUNCTION app_current_tenant_id() RETURNS uuid AS $$
        SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
      $$ LANGUAGE sql STABLE;
    SQL

    execute <<~SQL
      CREATE FUNCTION app_current_user_id() RETURNS uuid AS $$
        SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid
      $$ LANGUAGE sql STABLE;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS app_current_tenant_id();"
    execute "DROP FUNCTION IF EXISTS app_current_user_id();"
  end
end
