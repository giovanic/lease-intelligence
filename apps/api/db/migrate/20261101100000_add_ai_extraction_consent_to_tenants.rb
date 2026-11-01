# Per-organization consent for AI field extraction (docs/adr/0018): off by
# default — existing organizations included — until an owner/admin turns
# it on. Who last changed it, and when, is kept on the row (there is no
# audit module yet). `tenants` has no RLS (it is the tenancy anchor); the
# setting is only read and written for the tenant TenantScoped resolved.
class AddAiExtractionConsentToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :ai_extraction_enabled, :boolean, null: false, default: false
    add_column :tenants, :ai_extraction_changed_at, :datetime
    add_column :tenants, :ai_extraction_changed_by_id, :uuid
    add_foreign_key :tenants, :users, column: :ai_extraction_changed_by_id
    add_index :tenants, :ai_extraction_changed_by_id

    add_check_constraint :tenants,
      "(ai_extraction_changed_at IS NULL) = (ai_extraction_changed_by_id IS NULL)",
      name: "tenants_ai_extraction_change_recorded"
  end
end
