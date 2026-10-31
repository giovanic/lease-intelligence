# `users` is the global identity table (docs/domain/identity.md). It is
# intentionally NOT tenant-owned and carries no `tenant_id` — a user may
# hold memberships in multiple tenants, so tenancy is expressed entirely
# through `memberships`, never on this table. No RLS here, for the same
# reason there is none on `tenants`: there is nothing to scope by.
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      ## Devise :database_authenticatable
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Devise :recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Devise :rememberable
      t.datetime :remember_created_at

      ## Devise :trackable — audit value for this product's audit trail
      ## requirements (docs/architecture/security.md), not just Devise
      ## convenience.
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      t.string :full_name, null: false

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
