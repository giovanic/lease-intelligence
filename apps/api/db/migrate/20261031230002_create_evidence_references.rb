# Tenant-owned evidence of an ExtractedField (docs/adr/0011,
# docs/adr/0017-contract-field-extraction-claude.md): the page of the text
# the run read, and the character span of the quote inside that page's
# stored text. Only offsets are stored — the snippet is sliced from
# document_text_pages when served, so contract text is not duplicated.
# tenant_id + RLS are created here, in the same migration as the table.
#
# Append-only like extracted_fields (trigger rejects UPDATE/DELETE).
class CreateEvidenceReferences < ActiveRecord::Migration[8.1]
  def change
    # Composite-unique target for this table's (text_page_id, tenant_id) FK.
    add_index :document_text_pages, [ :id, :tenant_id ], unique: true, name: "idx_document_text_pages_id_tenant_id"

    create_table :evidence_references, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :extracted_field_id, null: false
      t.uuid :text_page_id, null: false
      t.integer :page_number, null: false
      # Character offsets into document_text_pages.text, end exclusive.
      t.integer :start_offset, null: false
      t.integer :end_offset, null: false

      t.datetime :created_at, null: false
    end

    add_foreign_key :evidence_references, :tenants, column: :tenant_id
    add_foreign_key :evidence_references, :extracted_fields, column: [ :extracted_field_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_evidence_references_field_same_tenant"
    add_foreign_key :evidence_references, :document_text_pages, column: [ :text_page_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_evidence_references_page_same_tenant"

    add_index :evidence_references, :tenant_id
    add_index :evidence_references, [ :extracted_field_id, :tenant_id ],
      name: "idx_evidence_references_field_id_tenant_id"
    add_index :evidence_references, [ :text_page_id, :tenant_id ], name: "idx_evidence_references_page_id_tenant_id"

    add_check_constraint :evidence_references, "page_number >= 1", name: "evidence_references_page_number_positive"
    add_check_constraint :evidence_references, "start_offset >= 0 AND end_offset > start_offset",
      name: "evidence_references_span_valid"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE evidence_references ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE evidence_references FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY evidence_references_tenant_isolation ON evidence_references
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE FUNCTION evidence_references_reject_change() RETURNS trigger
          LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'evidence_references rows are immutable (% rejected)', TG_OP
              USING ERRCODE = 'restrict_violation';
          END;
          $$;
        SQL
        execute <<~SQL
          CREATE TRIGGER evidence_references_immutable
            BEFORE UPDATE OR DELETE ON evidence_references
            FOR EACH ROW EXECUTE FUNCTION evidence_references_reject_change();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS evidence_references_immutable ON evidence_references;"
        execute "DROP FUNCTION IF EXISTS evidence_references_reject_change();"
        execute "DROP POLICY IF EXISTS evidence_references_tenant_isolation ON evidence_references;"
      end
    end
  end
end
