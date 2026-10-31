require "pundit/rspec"

# Policy layer of the three-layer tenant isolation test, shared by the
# portfolio policies (same role matrix). Expects `record_factory` (a
# factory name) to be defined by the including spec.
RSpec.shared_examples "a portfolio record policy" do |record_factory|
  subject { described_class }

  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }
  let(:record) { with_tenant(tenant) { create(record_factory, tenant: tenant) } }
  let(:other_tenant_record) { with_tenant(other_tenant) { create(record_factory, tenant: other_tenant) } }

  def context_for(role, status: "active", in_tenant: tenant)
    membership = with_tenant(in_tenant) { create(:membership, tenant: in_tenant, user: user, role: role, status: status) }
    AuthorizationContext.new(user: user, membership: membership)
  end

  permissions :index?, :show? do
    %w[owner admin manager analyst viewer].each do |role|
      it "allows an active #{role}" do
        expect(subject).to permit(context_for(role), record)
      end
    end
  end

  permissions :create?, :update? do
    %w[owner admin manager].each do |role|
      it "allows an active #{role}" do
        expect(subject).to permit(context_for(role), record)
      end
    end

    %w[analyst viewer].each do |role|
      it "denies an active #{role}" do
        expect(subject).not_to permit(context_for(role), record)
      end
    end
  end

  permissions :index?, :show?, :create?, :update? do
    it "denies a record of another tenant, even for an owner" do
      expect(subject).not_to permit(context_for("owner"), other_tenant_record)
    end

    it "denies a suspended membership" do
      expect(subject).not_to permit(context_for("owner", status: "suspended"), record)
    end

    it "denies without a tenant membership" do
      expect(subject).not_to permit(AuthorizationContext.new(user: user), record)
    end
  end

  permissions :destroy? do
    it "denies everyone: records are archived, not deleted" do
      expect(subject).not_to permit(context_for("owner"), record)
    end
  end

  permissions :index?, :create? do
    it "evaluates class-level checks against the current tenant" do
      expect(subject).to permit(context_for("manager"), record.class)
    end
  end

  describe "Scope" do
    it "returns only the current tenant's records" do
      context = context_for("viewer")
      own = record
      other_tenant_record

      resolved = with_tenant(tenant, user: user) { described_class::Scope.new(context, record.class).resolve.to_a }
      expect(resolved).to eq([ own ])
    end

    it "returns nothing without an active membership" do
      context = context_for("owner", status: "suspended")
      record

      resolved = with_tenant(tenant, user: user) { described_class::Scope.new(context, record.class).resolve.to_a }
      expect(resolved).to be_empty
    end
  end
end
