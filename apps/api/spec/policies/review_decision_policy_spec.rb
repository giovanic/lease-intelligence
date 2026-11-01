require "rails_helper"

# Policy layer of the three-layer isolation test for review decisions
# (docs/adr/0019): owners, admins, managers and analysts decide; viewers do
# not; nobody decides in another organization or changes a decision.
RSpec.describe ReviewDecisionPolicy do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }

  def context_for(role, status: "active", in_tenant: tenant)
    membership = with_tenant(in_tenant) { create(:membership, tenant: in_tenant, user: user, role: role, status: status) }
    AuthorizationContext.new(user: user, membership: membership)
  end

  %w[owner admin manager analyst].each do |role|
    it "lets an active #{role} decide" do
      expect(described_class.new(context_for(role), ReviewDecision).create?).to be(true)
    end
  end

  it "denies a viewer" do
    expect(described_class.new(context_for("viewer"), ReviewDecision).create?).to be(false)
  end

  it "denies a suspended membership and no membership" do
    [ context_for("owner", status: "suspended"), AuthorizationContext.new(user: user) ].each do |context|
      expect(described_class.new(context, ReviewDecision).create?).to be(false)
    end
  end

  it "never allows updating or destroying a decision, nor touching another tenant's" do
    decision = with_tenant(other_tenant) do
      version = create(:document_version, contract_document: create(:contract_document, tenant: other_tenant))
      run = create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: version))
      create(:review_decision, extracted_field: create(:extracted_field, extraction_run: run))
    end
    policy = described_class.new(context_for("owner"), decision)

    expect([ policy.show?, policy.update?, policy.destroy? ]).to eq([ false, false, false ])
  end
end
