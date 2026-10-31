# Tenant-owned join between a lease and its counterparties, with the role
# each one plays (docs/domain/leases.md): lessor (locador), guarantor
# (fiador) or intervening_party (interveniente anuente). tenant_id + RLS
# are created in the same migration as the table.
#
# Both sides use composite foreign keys onto (id, tenant_id), so a party
# row can never link a lease and a counterparty of different tenants —
# nor sit in a third tenant itself.
#
# "At least one lessor per lease" spans rows, so it is enforced by
# Leases::CreateLease / Leases::UpdateLease inside one transaction, not
# by a constraint here.
class CreateLeaseParties < ActiveRecord::Migration[8.1]
  def change
    create_table :lease_parties, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :lease_id, null: false
      t.uuid :counterparty_id, null: false
      t.string :role, null: false

      t.timestamps
    end

    add_foreign_key :lease_parties, :tenants, column: :tenant_id
    add_foreign_key :lease_parties, :leases, column: [ :lease_id, :tenant_id ], primary_key: [ :id, :tenant_id ],
      name: "fk_lease_parties_lease_same_tenant"
    add_foreign_key :lease_parties, :counterparties, column: [ :counterparty_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_lease_parties_counterparty_same_tenant"

    add_index :lease_parties, :tenant_id
    # A counterparty appears once per lease, in a single role.
    add_index :lease_parties, [ :lease_id, :counterparty_id ], unique: true, name: "idx_lease_parties_unique_per_lease"
    add_index :lease_parties, [ :counterparty_id, :tenant_id ], name: "idx_lease_parties_counterparty_id_tenant_id"

    add_check_constraint :lease_parties, "role IN ('lessor', 'guarantor', 'intervening_party')",
      name: "lease_parties_role_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE lease_parties ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE lease_parties FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY lease_parties_tenant_isolation ON lease_parties
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS lease_parties_tenant_isolation ON lease_parties;"
      end
    end
  end
end
