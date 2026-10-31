# Tenant-owned attempts at turning a DocumentVersion into per-page text
# (docs/adr/0016-document-text-extraction.md): native PDF text first, OCR
# for the pages without it. Reprocessing creates a new row; earlier attempts
# stay, so a later AI ExtractionRun can point at the exact text it read.
# tenant_id + RLS are created here, in the same migration as the table.
class CreateDocumentTextExtractions < ActiveRecord::Migration[8.1]
  def change
    # Composite-unique target for this table's (document_version_id, tenant_id) FK.
    add_index :document_versions, [ :id, :tenant_id ], unique: true, name: "idx_document_versions_id_tenant_id"

    create_table :document_text_extractions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :document_version_id, null: false
      t.string :status, null: false, default: "pending"
      # Null for the automatic run after an upload.
      t.uuid :requested_by_id
      t.integer :page_count
      t.integer :native_page_count
      t.integer :ocr_page_count
      t.string :native_engine
      t.string :ocr_engine
      # Fixed vocabulary (DocumentTextExtraction::ERROR_CODES), never an
      # exception message: messages can echo file content.
      t.string :error_code
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_foreign_key :document_text_extractions, :tenants, column: :tenant_id
    add_foreign_key :document_text_extractions, :document_versions, column: [ :document_version_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_document_text_extractions_version_same_tenant"
    add_foreign_key :document_text_extractions, :users, column: :requested_by_id

    add_index :document_text_extractions, :tenant_id
    add_index :document_text_extractions, [ :document_version_id, :tenant_id ],
      name: "idx_document_text_extractions_version_id_tenant_id"
    add_index :document_text_extractions, [ :document_version_id, :created_at ],
      name: "idx_document_text_extractions_version_latest"
    # Composite-unique target for document_text_pages' (text_extraction_id, tenant_id) FK.
    add_index :document_text_extractions, [ :id, :tenant_id ], unique: true,
      name: "idx_document_text_extractions_id_tenant_id"
    # At most one attempt in flight per version.
    add_index :document_text_extractions, :document_version_id, unique: true,
      where: "status IN ('pending', 'running')", name: "idx_document_text_extractions_one_active_per_version"
    add_index :document_text_extractions, :requested_by_id

    add_check_constraint :document_text_extractions, "status IN ('pending', 'running', 'succeeded', 'failed')",
      name: "document_text_extractions_status_check"
    add_check_constraint :document_text_extractions,
      "error_code IS NULL OR error_code IN ('unreadable_file', 'encrypted_pdf', 'too_many_pages', 'timeout', " \
      "'ocr_unavailable', 'storage_unavailable', 'abandoned', 'internal_error')",
      name: "document_text_extractions_error_code_check"
    add_check_constraint :document_text_extractions, "(status = 'failed') = (error_code IS NOT NULL)",
      name: "document_text_extractions_error_code_iff_failed"
    add_check_constraint :document_text_extractions,
      "status <> 'succeeded' OR (page_count >= 1 AND native_page_count >= 0 AND ocr_page_count >= 0 " \
      "AND native_page_count + ocr_page_count = page_count AND finished_at IS NOT NULL)",
      name: "document_text_extractions_succeeded_counts"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE document_text_extractions ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE document_text_extractions FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY document_text_extractions_tenant_isolation ON document_text_extractions
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS document_text_extractions_tenant_isolation ON document_text_extractions;"
      end
    end
  end
end
