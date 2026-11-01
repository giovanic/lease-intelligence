# Tenant-owned candidate values produced by an ExtractionRun
# (docs/adr/0017-contract-field-extraction-claude.md, docs/adr/0011). One
# typed column per kind of value — money is numeric(15,2) + currency, never
# a float or a JSON number — and a check that exactly the column matching
# `value_type` is set. Candidates, not facts: only a future ReviewDecision
# turns one into a contractual condition.
# tenant_id + RLS are created here, in the same migration as the table.
#
# A trigger rejects every UPDATE and DELETE: the AI output stays as it was
# produced, for audit and evaluation (a correction will be a ReviewDecision).
# Hence no updated_at.
class CreateExtractedFields < ActiveRecord::Migration[8.1]
  def change
    create_table :extracted_fields, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :extraction_run_id, null: false
      # Order of the candidate in the run's output (stable display order).
      t.integer :position, null: false
      t.string :field_key, null: false
      t.string :value_type, null: false
      t.date :value_date
      t.integer :value_integer
      t.decimal :value_amount, precision: 15, scale: 2
      t.string :value_currency
      # Option code, free text, or a party's name — contract content.
      t.text :value_text
      # CPF (11) or CNPJ (14) digits of a party — personal data.
      t.string :value_tax_id

      t.datetime :created_at, null: false
    end

    add_foreign_key :extracted_fields, :tenants, column: :tenant_id
    add_foreign_key :extracted_fields, :extraction_runs, column: [ :extraction_run_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_extracted_fields_run_same_tenant"

    add_index :extracted_fields, :tenant_id
    add_index :extracted_fields, [ :extraction_run_id, :position ], unique: true,
      name: "idx_extracted_fields_unique_position_per_run"
    add_index :extracted_fields, [ :extraction_run_id, :tenant_id ], name: "idx_extracted_fields_run_id_tenant_id"
    # Composite-unique target for evidence_references' (extracted_field_id, tenant_id) FK.
    add_index :extracted_fields, [ :id, :tenant_id ], unique: true, name: "idx_extracted_fields_id_tenant_id"

    add_check_constraint :extracted_fields, "position >= 0", name: "extracted_fields_position_non_negative"
    add_check_constraint :extracted_fields, "field_key ~ '^[a-z][a-z_]*$'", name: "extracted_fields_field_key_format"
    # COALESCE: a CHECK that evaluates to NULL passes, and `NULL ~ '...'` is
    # NULL — without it a money value with no currency would be accepted.
    add_check_constraint :extracted_fields, <<~SQL.squish, name: "extracted_fields_value_matches_type"
      COALESCE(CASE value_type
        WHEN 'date' THEN value_date IS NOT NULL AND value_integer IS NULL AND value_amount IS NULL
          AND value_currency IS NULL AND value_text IS NULL AND value_tax_id IS NULL
        WHEN 'integer' THEN value_integer IS NOT NULL AND value_date IS NULL AND value_amount IS NULL
          AND value_currency IS NULL AND value_text IS NULL AND value_tax_id IS NULL
        WHEN 'money' THEN value_amount IS NOT NULL AND value_amount >= 0 AND value_currency ~ '^[A-Z]{3}$'
          AND value_date IS NULL AND value_integer IS NULL AND value_text IS NULL AND value_tax_id IS NULL
        WHEN 'option' THEN value_text ~ '^[a-z][a-z_]*$' AND value_date IS NULL AND value_integer IS NULL
          AND value_amount IS NULL AND value_currency IS NULL AND value_tax_id IS NULL
        WHEN 'text' THEN value_text IS NOT NULL AND length(value_text) > 0 AND value_date IS NULL
          AND value_integer IS NULL AND value_amount IS NULL AND value_currency IS NULL AND value_tax_id IS NULL
        WHEN 'party' THEN value_text IS NOT NULL AND length(value_text) > 0
          AND (value_tax_id IS NULL OR value_tax_id ~ '^([0-9]{11}|[0-9]{14})$')
          AND value_date IS NULL AND value_integer IS NULL AND value_amount IS NULL AND value_currency IS NULL
        ELSE false
      END, false)
    SQL

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE extracted_fields ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE extracted_fields FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY extracted_fields_tenant_isolation ON extracted_fields
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE FUNCTION extracted_fields_reject_change() RETURNS trigger
          LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'extracted_fields rows are immutable (% rejected)', TG_OP
              USING ERRCODE = 'restrict_violation';
          END;
          $$;
        SQL
        execute <<~SQL
          CREATE TRIGGER extracted_fields_immutable
            BEFORE UPDATE OR DELETE ON extracted_fields
            FOR EACH ROW EXECUTE FUNCTION extracted_fields_reject_change();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS extracted_fields_immutable ON extracted_fields;"
        execute "DROP FUNCTION IF EXISTS extracted_fields_reject_change();"
        execute "DROP POLICY IF EXISTS extracted_fields_tenant_isolation ON extracted_fields;"
      end
    end
  end
end
