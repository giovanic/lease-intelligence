# `tenants` is the root tenancy anchor and is deliberately NOT subject to
# Row-Level Security: RLS protects tenant-OWNED data, but there is no
# "current tenant" to scope by until a user has resolved which tenants
# they belong to in the first place (docs/domain/identity.md). No code
# path may list all tenants indiscriminately — every real query against
# this table must go through the current user's `memberships` (enforced
# at the application/Pundit layer, not the database layer, for this
# table specifically).
class CreateTenants < ActiveRecord::Migration[8.0]
  def change
    create_table :tenants, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :tenants, :slug, unique: true
    add_check_constraint :tenants, "status IN ('active', 'suspended', 'canceled')", name: "tenants_status_check"
    add_check_constraint :tenants, "slug = lower(slug)", name: "tenants_slug_lowercase_check"
  end
end
