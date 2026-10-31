# Tenant-owned, append-only file versions of a contract document
# (docs/domain/documents.md, docs/adr/0010, docs/adr/0015). The row holds
# everything about the stored file — there are no Active Storage
# blobs/attachments tables — so its metadata (key, original filename,
# checksum) sits behind RLS like any other tenant data. tenant_id + RLS are
# created here, in the same migration as the table.
#
# Immutability is enforced by the database: a trigger rejects every UPDATE
# and DELETE, so a version can never be rewritten or removed by
# application code (a correction is a new version). Hence no updated_at.
class CreateDocumentVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :document_versions, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :contract_document_id, null: false
      t.integer :version_number, null: false
      t.string :storage_key, null: false
      t.string :original_filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false, limit: 64
      t.uuid :uploaded_by_id, null: false

      t.datetime :created_at, null: false
    end

    add_foreign_key :document_versions, :tenants, column: :tenant_id
    add_foreign_key :document_versions, :contract_documents, column: [ :contract_document_id, :tenant_id ],
      primary_key: [ :id, :tenant_id ], name: "fk_document_versions_document_same_tenant"
    add_foreign_key :document_versions, :users, column: :uploaded_by_id

    add_index :document_versions, :tenant_id
    add_index :document_versions, [ :contract_document_id, :version_number ], unique: true,
      name: "idx_document_versions_unique_number_per_document"
    add_index :document_versions, [ :contract_document_id, :tenant_id ],
      name: "idx_document_versions_document_id_tenant_id"
    add_index :document_versions, :storage_key, unique: true
    add_index :document_versions, :uploaded_by_id
    # The same bytes are stored once per tenant (docs/adr/0015 "duplicates").
    add_index :document_versions, [ :tenant_id, :sha256 ], unique: true,
      name: "idx_document_versions_unique_sha256_per_tenant"

    add_check_constraint :document_versions, "version_number >= 1", name: "document_versions_version_number_positive"
    add_check_constraint :document_versions, "sha256 ~ '^[0-9a-f]{64}$'", name: "document_versions_sha256_format"
    add_check_constraint :document_versions, "byte_size BETWEEN 1 AND 52428800", name: "document_versions_byte_size_range"
    add_check_constraint :document_versions,
      "content_type IN ('application/pdf', 'image/jpeg', 'image/png', 'image/tiff')",
      name: "document_versions_content_type_check"
    add_check_constraint :document_versions, "length(btrim(original_filename)) > 0",
      name: "document_versions_original_filename_present"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE document_versions FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY document_versions_tenant_isolation ON document_versions
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL

        execute <<~SQL
          CREATE FUNCTION document_versions_reject_change() RETURNS trigger
          LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'document_versions rows are immutable (% rejected)', TG_OP
              USING ERRCODE = 'restrict_violation';
          END;
          $$;
        SQL
        execute <<~SQL
          CREATE TRIGGER document_versions_immutable
            BEFORE UPDATE OR DELETE ON document_versions
            FOR EACH ROW EXECUTE FUNCTION document_versions_reject_change();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS document_versions_immutable ON document_versions;"
        execute "DROP FUNCTION IF EXISTS document_versions_reject_change();"
        execute "DROP POLICY IF EXISTS document_versions_tenant_isolation ON document_versions;"
      end
    end
  end
end
