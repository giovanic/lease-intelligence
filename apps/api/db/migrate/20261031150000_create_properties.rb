# Tenant-owned (docs/domain/portfolio.md, docs/adr/0002, docs/adr/0003):
# a leased physical location in a tenant's portfolio. tenant_id + RLS
# (ENABLE + FORCE + isolation policy) are created here, in the same
# migration as the table (docs/runbooks/database.md checklist).
#
# area_sqm is a measurement, not money, but still `decimal` — an area
# typed into a contract (e.g. 152,37 m²) must round-trip exactly.
class CreateProperties < ActiveRecord::Migration[8.0]
  def change
    create_table :properties, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.string :name, null: false
      t.string :code
      t.string :property_type, null: false
      t.string :status, null: false, default: "active"
      t.string :street, null: false
      t.string :number
      t.string :complement
      t.string :district
      t.string :city, null: false
      t.string :state, null: false
      t.string :postal_code
      t.string :country_code, null: false, default: "BR"
      t.decimal :area_sqm, precision: 12, scale: 2

      t.timestamps
    end

    add_foreign_key :properties, :tenants, column: :tenant_id

    add_index :properties, :tenant_id
    # Composite-unique target for future (property_id, tenant_id) foreign
    # keys from leases (docs/architecture/multi-tenancy.md "composite
    # foreign keys"), so the database rejects a lease pointing at another
    # tenant's property.
    add_index :properties, [ :id, :tenant_id ], unique: true, name: "idx_properties_id_tenant_id"
    # Optional internal unit code (e.g. "SP-014"), unique within a tenant.
    add_index :properties, [ :tenant_id, :code ], unique: true, where: "code IS NOT NULL",
      name: "idx_properties_unique_code_per_tenant"

    add_check_constraint :properties,
      "property_type IN ('retail', 'clinic', 'office', 'restaurant', 'gym', 'school', 'warehouse', 'other')",
      name: "properties_property_type_check"
    add_check_constraint :properties, "status IN ('active', 'archived')", name: "properties_status_check"
    add_check_constraint :properties, "state ~ '^[A-Z]{2}$'", name: "properties_state_format_check"
    add_check_constraint :properties, "country_code ~ '^[A-Z]{2}$'", name: "properties_country_code_format_check"
    add_check_constraint :properties, "postal_code IS NULL OR postal_code ~ '^[0-9]{8}$'",
      name: "properties_postal_code_format_check"
    add_check_constraint :properties, "area_sqm IS NULL OR area_sqm > 0", name: "properties_area_sqm_positive_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE properties ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE properties FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY properties_tenant_isolation ON properties
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS properties_tenant_isolation ON properties;"
      end
    end
  end
end
