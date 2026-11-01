require "rails_helper"

RSpec.describe Tenant, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:memberships) }
    it { is_expected.to have_many(:users).through(:memberships) }
    it { is_expected.to have_many(:invitations) }
  end

  describe "validations" do
    subject { build(:tenant) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug).ignoring_case_sensitivity }

    it "rejects a slug with uppercase or invalid characters" do
      tenant = build(:tenant, slug: "Not Valid Slug!")
      expect(tenant).not_to be_valid
      expect(tenant.errors[:slug]).to be_present
    end

    it "downcases the slug before validation" do
      tenant = build(:tenant, slug: "MixedCase-Slug")
      tenant.valid?
      expect(tenant.slug).to eq("mixedcase-slug")
    end
  end

  describe "status enum" do
    it "defaults to active" do
      expect(Tenant.new.status).to eq("active")
    end

    it "only allows the documented statuses at the database level" do
      tenant = create(:tenant)
      expect {
        ActiveRecord::Base.connection.execute(
          "UPDATE tenants SET status = 'not_a_real_status' WHERE id = #{ActiveRecord::Base.connection.quote(tenant.id)}"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /tenants_status_check/)
    end
  end

  describe "database constraints" do
    it "rejects a duplicate slug at the database level even bypassing Rails validations" do
      create(:tenant, slug: "duplicate-slug")

      expect {
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO tenants (id, name, slug, status, created_at, updated_at)
          VALUES (gen_random_uuid(), 'Other', 'duplicate-slug', 'active', now(), now())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "starts with AI extraction off and requires who and when to be recorded together (docs/adr/0018)" do
      tenant = create(:tenant)
      expect(tenant.reload.ai_extraction_enabled).to be(false)

      expect { tenant.update_columns(ai_extraction_changed_at: Time.current) }
        .to raise_error(ActiveRecord::StatementInvalid, /tenants_ai_extraction_change_recorded/)
    end
  end
end
