require "rails_helper"
require "pundit/rspec"

# Policy layer of the three-layer tenant isolation test for documents.
# Any active member reads; owners/admins/managers upload and request text
# extractions and AI field extraction runs; nobody updates or destroys
# (versions are immutable, docs/adr/0010; extractions and runs change only
# through the pipeline, docs/adr/0016, docs/adr/0017).
RSpec.describe "Document policies" do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:user) { create(:user) }
  let!(:document) { with_tenant(tenant) { create(:contract_document, tenant: tenant) } }
  let!(:version) { with_tenant(tenant) { create(:document_version, contract_document: document) } }
  let!(:other_document) { with_tenant(other_tenant) { create(:contract_document, tenant: other_tenant) } }
  let!(:other_version) { with_tenant(other_tenant) { create(:document_version, contract_document: other_document) } }
  let!(:extraction) { with_tenant(tenant) { create(:document_text_extraction, document_version: version) } }
  let!(:other_extraction) do
    with_tenant(other_tenant) { create(:document_text_extraction, document_version: other_version) }
  end
  let!(:run) { with_tenant(tenant) { create(:extraction_run, text_extraction: extraction) } }
  let!(:other_run) { with_tenant(other_tenant) { create(:extraction_run, text_extraction: other_extraction) } }
  let(:records) do
    { ContractDocumentPolicy => document, DocumentVersionPolicy => version, DocumentTextExtractionPolicy => extraction,
      ExtractionRunPolicy => run }
  end
  let(:other_tenant_records) do
    { ContractDocumentPolicy => other_document, DocumentVersionPolicy => other_version,
      DocumentTextExtractionPolicy => other_extraction, ExtractionRunPolicy => other_run }
  end

  def context_for(role, status: "active")
    membership = with_tenant(tenant) { create(:membership, tenant: tenant, user: user, role: role, status: status) }
    AuthorizationContext.new(user: user, membership: membership)
  end

  {
    ContractDocumentPolicy => { read: %i[index? show?], write: %i[create?], never: %i[update? destroy?] },
    DocumentVersionPolicy => { read: %i[show?], write: %i[create?], never: %i[update? destroy?] },
    # Status is read through the version; the extraction itself has no read action yet.
    DocumentTextExtractionPolicy => { read: [], write: %i[create?], never: %i[index? show? update? destroy?] },
    # Reading a run (fields + quoted evidence) is open to the same members
    # who can download the file; requesting one costs a provider call.
    ExtractionRunPolicy => { read: %i[show?], write: %i[create?], never: %i[index? update? destroy?] }
  }.each do |policy, actions|
    describe policy do
      let(:record) { records.fetch(policy) }
      let(:other_tenant_record) { other_tenant_records.fetch(policy) }

      %w[owner admin manager analyst viewer].each do |role|
        it "lets an active #{role} read" do
          context = context_for(role)
          actions[:read].each { |action| expect(policy.new(context, record).public_send(action)).to be(true) }
        end
      end

      %w[owner admin manager].each do |role|
        it "lets an active #{role} upload" do
          context = context_for(role)
          actions[:write].each { |action| expect(policy.new(context, record.class).public_send(action)).to be(true) }
        end
      end

      %w[analyst viewer].each do |role|
        it "denies upload to an active #{role}" do
          context = context_for(role)
          actions[:write].each { |action| expect(policy.new(context, record.class).public_send(action)).to be(false) }
        end
      end

      it "denies everything on another tenant's record, even to an owner" do
        context = context_for("owner")
        (actions[:read] + actions[:never]).each do |action|
          expect(policy.new(context, other_tenant_record).public_send(action)).to be(false)
        end
      end

      it "denies everything to a suspended membership and without a membership" do
        [ context_for("owner", status: "suspended"), AuthorizationContext.new(user: user) ].each do |context|
          (actions[:read] + actions[:never]).each do |action|
            expect(policy.new(context, record).public_send(action)).to be(false)
          end
          actions[:write].each { |action| expect(policy.new(context, record.class).public_send(action)).to be(false) }
        end
      end

      it "never allows update or destroy" do
        context = context_for("owner")
        actions[:never].each { |action| expect(policy.new(context, record).public_send(action)).to be(false) }
      end

      it "scopes to the current tenant's records" do
        context = context_for("viewer")

        resolved = with_tenant(tenant, user: user) { policy::Scope.new(context, record.class).resolve.to_a }
        expect(resolved).to eq([ record ])
      end
    end
  end
end
