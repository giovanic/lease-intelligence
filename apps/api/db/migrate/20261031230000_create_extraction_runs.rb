# Tenant-owned AI field extraction runs over a DocumentVersion
# (docs/adr/0017-contract-field-extraction-claude.md). Each run points at
# the exact DocumentTextExtraction it read, and records provider, model,
# model version, prompt version, effort and token usage, so any field can
# be traced to how it was produced. Reprocessing creates a new row.
# tenant_id + RLS are created here, in the same migration as the table.
class CreateExtractionRuns < ActiveRecord::Migration[8.1]
  def change
    # Composite-unique target for this table's (text_extraction_id,
    # document_version_id, tenant_id) FK: the text a run read must belong to
    # the run's own version.
    add_index :document_text_extractions, [ :id, :document_version_id, :tenant_id ], unique: true,
      name: "idx_document_text_extractions_id_version_id_tenant_id"

    create_table :extraction_runs, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :document_version_id, null: false
      t.uuid :text_extraction_id, null: false
      t.string :status, null: false, default: "pending"
      # Null for the automatic run after a text extraction.
      t.uuid :requested_by_id
      t.string :provider, null: false
      # The model asked for; model_version is the one that answered (a
      # server-side fallback may differ).
      t.string :model, null: false
      t.string :model_version
      t.string :prompt_version, null: false
      t.string :effort, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_input_tokens
      t.integer :cache_creation_input_tokens
      t.integer :duration_ms
      t.integer :field_count
      t.integer :rejected_field_count
      # Fixed vocabulary (ExtractionRun::ERROR_CODES), never a provider
      # message: it could echo contract content.
      t.string :error_code
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_foreign_key :extraction_runs, :tenants, column: :tenant_id
    add_foreign_key :extraction_runs, :document_versions, column: [ :document_version_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_extraction_runs_version_same_tenant"
    add_foreign_key :extraction_runs, :document_text_extractions,
      column: [ :text_extraction_id, :document_version_id, :tenant_id ],
      primary_key: [ :id, :document_version_id, :tenant_id ], name: "fk_extraction_runs_text_same_version"
    add_foreign_key :extraction_runs, :users, column: :requested_by_id

    add_index :extraction_runs, :tenant_id
    add_index :extraction_runs, [ :document_version_id, :tenant_id ], name: "idx_extraction_runs_version_id_tenant_id"
    add_index :extraction_runs, [ :document_version_id, :created_at ], name: "idx_extraction_runs_version_latest"
    add_index :extraction_runs, [ :text_extraction_id, :document_version_id, :tenant_id ],
      name: "idx_extraction_runs_text_extraction"
    # Composite-unique target for extracted_fields' (extraction_run_id, tenant_id) FK.
    add_index :extraction_runs, [ :id, :tenant_id ], unique: true, name: "idx_extraction_runs_id_tenant_id"
    # At most one run in flight per version.
    add_index :extraction_runs, :document_version_id, unique: true,
      where: "status IN ('pending', 'running')", name: "idx_extraction_runs_one_active_per_version"
    add_index :extraction_runs, :requested_by_id

    add_check_constraint :extraction_runs, "status IN ('pending', 'running', 'succeeded', 'failed')",
      name: "extraction_runs_status_check"
    add_check_constraint :extraction_runs,
      "error_code IS NULL OR error_code IN ('rate_limited', 'provider_unavailable', 'timeout', 'output_truncated', " \
      "'refused', 'invalid_output', 'text_too_long', 'abandoned', 'internal_error')",
      name: "extraction_runs_error_code_check"
    add_check_constraint :extraction_runs, "(status = 'failed') = (error_code IS NOT NULL)",
      name: "extraction_runs_error_code_iff_failed"
    # COALESCE: `NULL >= 0` is NULL, and a CHECK that evaluates to NULL passes.
    add_check_constraint :extraction_runs,
      "status <> 'succeeded' OR (COALESCE(field_count >= 0 AND rejected_field_count >= 0, false) " \
      "AND model_version IS NOT NULL AND finished_at IS NOT NULL)",
      name: "extraction_runs_succeeded_counts"
    add_check_constraint :extraction_runs,
      "COALESCE(input_tokens, 0) >= 0 AND COALESCE(output_tokens, 0) >= 0 " \
      "AND COALESCE(cache_read_input_tokens, 0) >= 0 AND COALESCE(cache_creation_input_tokens, 0) >= 0 " \
      "AND COALESCE(duration_ms, 0) >= 0",
      name: "extraction_runs_usage_non_negative"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE extraction_runs ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE extraction_runs FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY extraction_runs_tenant_isolation ON extraction_runs
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS extraction_runs_tenant_isolation ON extraction_runs;"
      end
    end
  end
end
