# Tenant-owned (docs/domain/portfolio.md, docs/adr/0002, docs/adr/0003):
# the landlord/lessor side of a lease — a person or legal entity, never a
# platform User. tenant_id + RLS are created in the same migration as the
# table (docs/runbooks/database.md checklist).
#
# tax_id holds digits only: a CPF (11) for an individual, a CNPJ (14) for
# a company. It is optional because the lessor's document is not always
# known when the record is first registered, but when present it must
# match the kind and be unique within the tenant. A CPF is personal data
# under LGPD — it is filtered from logs (filter_parameter_logging.rb).
class CreateCounterparties < ActiveRecord::Migration[8.0]
  def change
    create_table :counterparties, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.string :kind, null: false
      t.string :legal_name, null: false
      t.string :trade_name
      t.string :tax_id
      t.string :email
      t.string :phone
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_foreign_key :counterparties, :tenants, column: :tenant_id

    add_index :counterparties, :tenant_id
    # Composite-unique target for future (counterparty_id, tenant_id)
    # foreign keys from the lease <-> counterparty join.
    add_index :counterparties, [ :id, :tenant_id ], unique: true, name: "idx_counterparties_id_tenant_id"
    add_index :counterparties, [ :tenant_id, :tax_id ], unique: true, where: "tax_id IS NOT NULL",
      name: "idx_counterparties_unique_tax_id_per_tenant"

    add_check_constraint :counterparties, "kind IN ('individual', 'company')", name: "counterparties_kind_check"
    add_check_constraint :counterparties, "status IN ('active', 'archived')", name: "counterparties_status_check"
    add_check_constraint :counterparties,
      "tax_id IS NULL OR (kind = 'individual' AND tax_id ~ '^[0-9]{11}$') OR (kind = 'company' AND tax_id ~ '^[0-9]{14}$')",
      name: "counterparties_tax_id_format_check"
    add_check_constraint :counterparties, "email IS NULL OR email = lower(email)",
      name: "counterparties_email_lowercase_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE counterparties ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE counterparties FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY counterparties_tenant_isolation ON counterparties
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS counterparties_tenant_isolation ON counterparties;"
      end
    end
  end
end
