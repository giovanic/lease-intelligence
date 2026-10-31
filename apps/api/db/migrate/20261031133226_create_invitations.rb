# Tenant-owned (docs/architecture/multi-tenancy.md, docs/adr/0003). An
# invitation targets an email address, not necessarily an existing User —
# the invitee may not have an account yet. Standard tenant isolation only:
# the token-based lookup needed by the (not-yet-built) accept-invitation
# endpoint — where the invitee has no tenant context at all — is a known,
# deliberately deferred follow-up; see docs/domain/identity.md "Open
# questions" and docs/adr/0003-postgresql-rls.md.
class CreateInvitations < ActiveRecord::Migration[8.0]
  def change
    create_table :invitations, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :invited_by_id, null: false
      t.string :email, null: false
      t.string :role, null: false
      t.string :status, null: false, default: "pending"
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_foreign_key :invitations, :tenants, column: :tenant_id
    add_foreign_key :invitations, :users, column: :invited_by_id

    add_index :invitations, :tenant_id
    add_index :invitations, :invited_by_id
    add_index :invitations, :token, unique: true
    # Composite-unique target for memberships' composite foreign key
    # (docs/architecture/multi-tenancy.md "composite foreign keys") — lets
    # memberships.(invitation_id, tenant_id) reference this pair, so the
    # database itself rejects a membership whose invitation belongs to a
    # different tenant.
    add_index :invitations, [ :id, :tenant_id ], unique: true, name: "idx_invitations_id_tenant_id"
    # A tenant may have at most one pending invitation per email at a
    # time — re-inviting first requires revoking/expiring the prior one.
    add_index :invitations, [ :tenant_id, :email ], unique: true,
      where: "status = 'pending'", name: "idx_invitations_unique_pending_per_tenant_email"

    add_check_constraint :invitations, "role IN ('owner', 'admin', 'manager', 'analyst', 'viewer')",
      name: "invitations_role_check"
    add_check_constraint :invitations, "status IN ('pending', 'accepted', 'revoked', 'expired')",
      name: "invitations_status_check"
    add_check_constraint :invitations, "email = lower(email)", name: "invitations_email_lowercase_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE invitations FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY invitations_tenant_isolation ON invitations
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS invitations_tenant_isolation ON invitations;"
      end
    end
  end
end
