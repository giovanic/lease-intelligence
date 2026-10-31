# Tenant-owned (docs/domain/leases.md, docs/adr/0002, docs/adr/0003): the
# registration record of a commercial lease — which property, under which
# internal title/code, in which lifecycle status. tenant_id + RLS (ENABLE +
# FORCE + isolation policy) are created here, in the same migration as the
# table (docs/runbooks/database.md checklist).
#
# Deliberately no dates, rent or indexation columns: contractual terms are
# effective-dated ContractualConditions approved through human review
# (docs/adr/0010, docs/adr/0011), never typed onto the lease itself.
class CreateLeases < ActiveRecord::Migration[8.1]
  def change
    create_table :leases, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :property_id, null: false
      t.string :title, null: false
      t.string :code
      t.string :status, null: false, default: "draft"
      t.text :notes

      t.timestamps
    end

    add_foreign_key :leases, :tenants, column: :tenant_id
    # Composite FK onto properties' unique (id, tenant_id): the database
    # itself rejects a lease of tenant A pointing at a property of tenant B
    # (docs/architecture/multi-tenancy.md "composite foreign keys").
    add_foreign_key :leases, :properties, column: [ :property_id, :tenant_id ], primary_key: [ :id, :tenant_id ],
      name: "fk_leases_property_same_tenant"

    add_index :leases, :tenant_id
    add_index :leases, [ :property_id, :tenant_id ], name: "idx_leases_property_id_tenant_id"
    # Composite-unique target for the (lease_id, tenant_id) foreign keys of
    # lease_parties and of the future documents/conditions tables.
    add_index :leases, [ :id, :tenant_id ], unique: true, name: "idx_leases_id_tenant_id"
    # Optional internal contract code (e.g. "LOC-2024-017"), unique within a tenant.
    add_index :leases, [ :tenant_id, :code ], unique: true, where: "code IS NOT NULL",
      name: "idx_leases_unique_code_per_tenant"

    add_check_constraint :leases, "status IN ('draft', 'active', 'expired', 'terminated')", name: "leases_status_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE leases ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE leases FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY leases_tenant_isolation ON leases
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS leases_tenant_isolation ON leases;"
      end
    end
  end
end
