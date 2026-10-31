# Tenant-owned, append-only text of one page of a DocumentTextExtraction
# (docs/adr/0016-document-text-extraction.md). `source` says whether the
# text came from the PDF itself or from OCR. The text is contract content:
# behind FORCE RLS, never logged, not returned by the API in this phase.
# tenant_id + RLS are created here, in the same migration as the table.
#
# Like document_versions, a trigger rejects every UPDATE and DELETE: an
# attempt's pages are written once, when it succeeds, and never rewritten
# (a new attempt is a new extraction). Hence no updated_at.
class CreateDocumentTextPages < ActiveRecord::Migration[8.1]
  def change
    create_table :document_text_pages, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :text_extraction_id, null: false
      t.integer :page_number, null: false
      t.string :source, null: false
      t.text :text, null: false

      t.datetime :created_at, null: false
    end

    add_foreign_key :document_text_pages, :tenants, column: :tenant_id
    add_foreign_key :document_text_pages, :document_text_extractions, column: [ :text_extraction_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_document_text_pages_extraction_same_tenant"

    add_index :document_text_pages, :tenant_id
    add_index :document_text_pages, [ :text_extraction_id, :page_number ], unique: true,
      name: "idx_document_text_pages_unique_number_per_extraction"
    add_index :document_text_pages, [ :text_extraction_id, :tenant_id ],
      name: "idx_document_text_pages_extraction_id_tenant_id"

    add_check_constraint :document_text_pages, "page_number >= 1", name: "document_text_pages_page_number_positive"
    add_check_constraint :document_text_pages, "source IN ('native', 'ocr')", name: "document_text_pages_source_check"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE document_text_pages ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE document_text_pages FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY document_text_pages_tenant_isolation ON document_text_pages
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE FUNCTION document_text_pages_reject_change() RETURNS trigger
          LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'document_text_pages rows are immutable (% rejected)', TG_OP
              USING ERRCODE = 'restrict_violation';
          END;
          $$;
        SQL
        execute <<~SQL
          CREATE TRIGGER document_text_pages_immutable
            BEFORE UPDATE OR DELETE ON document_text_pages
            FOR EACH ROW EXECUTE FUNCTION document_text_pages_reject_change();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS document_text_pages_immutable ON document_text_pages;"
        execute "DROP FUNCTION IF EXISTS document_text_pages_reject_change();"
        execute "DROP POLICY IF EXISTS document_text_pages_tenant_isolation ON document_text_pages;"
      end
    end
  end
end
