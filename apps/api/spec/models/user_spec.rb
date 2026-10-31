require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:memberships) }
    it { is_expected.to have_many(:tenants).through(:memberships) }
    it { is_expected.to have_many(:sent_invitations).class_name("Invitation") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:full_name) }

    it "requires a unique email" do
      create(:user, email: "taken@example.com")
      duplicate = build(:user, email: "taken@example.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it "requires a password via Devise :validatable" do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
    end
  end

  it "carries no tenant_id column — tenancy is only via memberships" do
    expect(User.column_names).not_to include("tenant_id")
  end

  describe "database constraints" do
    it "rejects a duplicate email at the database level" do
      create(:user, email: "dup@example.com")

      expect {
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO users (id, email, encrypted_password, full_name, created_at, updated_at)
          VALUES (gen_random_uuid(), 'dup@example.com', 'x', 'Someone', now(), now())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
