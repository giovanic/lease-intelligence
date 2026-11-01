# Tenant-owned human decisions on AI-extracted fields (docs/adr/0012,
# docs/adr/0019): approved as is, corrected (approved with the reviewer's
# value) or rejected. Append-only — changing one's mind is a new row; a
# field's current state is its latest decision.
# tenant_id + RLS are created here, in the same migration as the table.
#
# A corrected value uses the same typed columns as extracted_fields, and
# `value_type` is copied from the field and pinned by a composite FK to
# extracted_fields (id, value_type, tenant_id): a correction can never have
# another type than the field it corrects.
class CreateReviewDecisions < ActiveRecord::Migration[8.1]
  def change
    # Composite-unique target for this table's (extracted_field_id, value_type, tenant_id) FK.
    add_index :extracted_fields, [ :id, :value_type, :tenant_id ], unique: true,
      name: "idx_extracted_fields_id_value_type_tenant_id"

    create_table :review_decisions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :extracted_field_id, null: false
      t.string :value_type, null: false
      t.string :decision, null: false
      t.date :value_date
      t.integer :value_integer
      t.decimal :value_amount, precision: 15, scale: 2
      t.string :value_currency
      # Corrected option code, text or party name — contract content.
      t.text :value_text
      t.string :value_tax_id
      t.text :reason
      t.uuid :reviewed_by_id, null: false

      t.datetime :created_at, null: false
    end

    add_foreign_key :review_decisions, :tenants, column: :tenant_id
    add_foreign_key :review_decisions, :extracted_fields, column: [ :extracted_field_id, :value_type, :tenant_id ],
      primary_key: [ :id, :value_type, :tenant_id ], name: "fk_review_decisions_field_same_type_and_tenant"
    add_foreign_key :review_decisions, :users, column: :reviewed_by_id

    add_index :review_decisions, :tenant_id
    add_index :review_decisions, [ :extracted_field_id, :value_type, :tenant_id ],
      name: "idx_review_decisions_field_type_tenant"
    add_index :review_decisions, [ :extracted_field_id, :created_at ], name: "idx_review_decisions_field_latest"
    add_index :review_decisions, :reviewed_by_id

    add_check_constraint :review_decisions, "decision IN ('approved', 'corrected', 'rejected')",
      name: "review_decisions_decision_check"
    add_check_constraint :review_decisions, "reason IS NULL OR (length(reason) BETWEEN 1 AND 1000)",
      name: "review_decisions_reason_length"
    # COALESCE: a CHECK that evaluates to NULL passes, and `NULL ~ '...'` is NULL.
    add_check_constraint :review_decisions, <<~SQL.squish, name: "review_decisions_value_matches_decision"
      COALESCE(CASE
        WHEN decision IN ('approved', 'rejected') THEN value_date IS NULL AND value_integer IS NULL
          AND value_amount IS NULL AND value_currency IS NULL AND value_text IS NULL AND value_tax_id IS NULL
        ELSE CASE value_type
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
        END
      END, false)
    SQL

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE review_decisions ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE review_decisions FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY review_decisions_tenant_isolation ON review_decisions
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE FUNCTION review_decisions_reject_change() RETURNS trigger
          LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'review_decisions rows are immutable (% rejected)', TG_OP
              USING ERRCODE = 'restrict_violation';
          END;
          $$;
        SQL
        execute <<~SQL
          CREATE TRIGGER review_decisions_immutable
            BEFORE UPDATE OR DELETE ON review_decisions
            FOR EACH ROW EXECUTE FUNCTION review_decisions_reject_change();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS review_decisions_immutable ON review_decisions;"
        execute "DROP FUNCTION IF EXISTS review_decisions_reject_change();"
        execute "DROP POLICY IF EXISTS review_decisions_tenant_isolation ON review_decisions;"
      end
    end
  end
end
