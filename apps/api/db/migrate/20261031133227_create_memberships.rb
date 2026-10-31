# Tenant-owned join of User <-> Tenant (docs/domain/identity.md). Carries
# the role used by Pundit policies. RLS here has two PERMISSIVE policies
# that Postgres combines with OR for SELECT: the standard tenant-isolation
# policy, plus a narrow self-visibility policy that lets a user see their
# OWN membership rows regardless of which tenant is currently active —
# required to bootstrap "which organizations am I in" before any tenant
# has been selected (docs/adr/0003-postgresql-rls.md). The self-visibility
# policy is SELECT-only: writes always require the acting tenant context
# to match, so a user cannot self-escalate a role or leave an org without
# that org's tenant context active.
class CreateMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :memberships, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :user_id, null: false
      t.uuid :invitation_id
      t.string :role, null: false
      t.string :status, null: false, default: "active"
      t.datetime :deactivated_at

      t.timestamps
    end

    add_foreign_key :memberships, :tenants, column: :tenant_id
    add_foreign_key :memberships, :users, column: :user_id
    # No plain `invitation_id -> invitations.id` foreign key here — the
    # composite foreign key added below (invitation_id, tenant_id) ->
    # (id, tenant_id) already implies it, and adding both would be a
    # redundant constraint.

    add_index :memberships, :tenant_id
    add_index :memberships, :user_id
    add_index :memberships, [ :tenant_id, :user_id ], unique: true
    add_index :memberships, :invitation_id, unique: true

    add_check_constraint :memberships, "role IN ('owner', 'admin', 'manager', 'analyst', 'viewer')",
      name: "memberships_role_check"
    add_check_constraint :memberships, "status IN ('active', 'suspended')",
      name: "memberships_status_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE memberships FORCE ROW LEVEL SECURITY;"

        execute <<~SQL
          CREATE POLICY memberships_tenant_isolation ON memberships
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE POLICY memberships_self_visibility ON memberships
            FOR SELECT
            USING (user_id = app_current_user_id());
        SQL

        # Composite foreign key (docs/architecture/multi-tenancy.md
        # "composite foreign keys"): if a membership was created from an
        # invitation, that invitation must belong to the SAME tenant.
        # A plain CHECK constraint can't reference another table in
        # Postgres, so this is a real composite FK against the
        # (id, tenant_id) unique index created on invitations. With the
        # default MATCH SIMPLE semantics, a NULL invitation_id (no
        # invitation involved) is simply exempt from the check — only a
        # non-null invitation_id must resolve to a same-tenant invitation
        # row.
        execute <<~SQL
          ALTER TABLE memberships
            ADD CONSTRAINT memberships_invitation_same_tenant
            FOREIGN KEY (invitation_id, tenant_id)
            REFERENCES invitations (id, tenant_id);
        SQL
      end

      dir.down do
        execute "ALTER TABLE memberships DROP CONSTRAINT IF EXISTS memberships_invitation_same_tenant;"
        execute "DROP POLICY IF EXISTS memberships_self_visibility ON memberships;"
        execute "DROP POLICY IF EXISTS memberships_tenant_isolation ON memberships;"
      end
    end
  end
end
