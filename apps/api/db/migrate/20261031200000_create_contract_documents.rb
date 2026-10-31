# Tenant-owned (docs/domain/documents.md): the conceptual document slot of
# a lease — "the original contract", "amendment #2" — whose files are its
# immutable document_versions. tenant_id + RLS (ENABLE + FORCE + isolation
# policy) are created here, in the same migration as the table
# (docs/runbooks/database.md checklist).
class CreateContractDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_documents, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :lease_id, null: false
      t.string :kind, null: false
      t.string :title, null: false

      t.timestamps
    end

    add_foreign_key :contract_documents, :tenants, column: :tenant_id
    # Composite FK onto leases' unique (id, tenant_id): a document of tenant
    # A can never hang from a lease of tenant B.
    add_foreign_key :contract_documents, :leases, column: [ :lease_id, :tenant_id ], primary_key: [ :id, :tenant_id ],
      name: "fk_contract_documents_lease_same_tenant"

    add_index :contract_documents, :tenant_id
    add_index :contract_documents, [ :lease_id, :tenant_id ], name: "idx_contract_documents_lease_id_tenant_id"
    # Composite-unique target for document_versions' (contract_document_id, tenant_id) FK.
    add_index :contract_documents, [ :id, :tenant_id ], unique: true, name: "idx_contract_documents_id_tenant_id"
    # A lease has at most one original contract; amendments and other documents are unlimited.
    add_index :contract_documents, :lease_id, unique: true, where: "kind = 'original_contract'",
      name: "idx_contract_documents_one_original_per_lease"

    add_check_constraint :contract_documents, "kind IN ('original_contract', 'amendment', 'other')",
      name: "contract_documents_kind_check"
    add_check_constraint :contract_documents, "length(btrim(title)) > 0", name: "contract_documents_title_present"

    reversible do |dir|
      dir.up do
        execute "ALTER TABLE contract_documents ENABLE ROW LEVEL SECURITY;"
        execute "ALTER TABLE contract_documents FORCE ROW LEVEL SECURITY;"
        execute <<~SQL
          CREATE POLICY contract_documents_tenant_isolation ON contract_documents
            USING (tenant_id = app_current_tenant_id())
            WITH CHECK (tenant_id = app_current_tenant_id());
        SQL
      end

      dir.down do
        execute "DROP POLICY IF EXISTS contract_documents_tenant_isolation ON contract_documents;"
      end
    end
  end
end
