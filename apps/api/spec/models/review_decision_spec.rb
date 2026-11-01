require "rails_helper"

# docs/adr/0019-review-decisions.md
RSpec.describe ReviewDecision, type: :model do
  let(:tenant) { create(:tenant) }
  let(:other_tenant) { create(:tenant) }
  let(:connection) { ActiveRecord::Base.connection }
  let(:reviewer) { create(:user) }

  def create_field(tenant, **attributes)
    version = create(:document_version, contract_document: create(:contract_document, tenant: tenant))
    run = create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: version))
    create(:extracted_field, extraction_run: run, **attributes)
  end

  let!(:field) { with_tenant(tenant) { create_field(tenant) } } # integer, term_months = 60
  let!(:money_field) do
    with_tenant(tenant) do
      create_field(tenant, field_key: "monthly_rent", value_type: "money", value_integer: nil,
        value_amount: BigDecimal("10000"), value_currency: "BRL")
    end
  end
  let!(:other_field) { with_tenant(other_tenant) { create_field(other_tenant) } }

  def save_raw(target = field, **attributes)
    with_tenant(tenant) do
      build(:review_decision, extracted_field: target, reviewed_by: reviewer, **attributes).save!(validate: false)
    end
  end

  it "is read-only once persisted" do
    decision = with_tenant(tenant) { create(:review_decision, extracted_field: field, reviewed_by: reviewer) }

    expect(decision).to be_readonly
  end

  describe "database guarantees" do
    it "stores an exact corrected amount with its currency" do
      decision = with_tenant(tenant) do
        create(:review_decision, extracted_field: money_field, reviewed_by: reviewer, decision: "corrected",
          value_amount: BigDecimal("9999999999999.99"), value_currency: "BRL")
      end

      expect(with_tenant(tenant) { decision.reload.value_amount }).to eq(BigDecimal("9999999999999.99"))
    end

    it "requires a value of the field's type for a correction, and none for an approval or rejection" do
      check = /review_decisions_value_matches_decision/

      expect { save_raw(decision: "corrected") }.to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(decision: "approved", value_integer: 12) }.to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(decision: "rejected", value_text: "x") }.to raise_error(ActiveRecord::StatementInvalid, check)
      expect { save_raw(money_field, decision: "corrected", value_amount: BigDecimal("10")) }
        .to raise_error(ActiveRecord::StatementInvalid, check)
    end

    it "rejects a correction typed differently from the field it corrects" do
      expect { save_raw(decision: "corrected", value_type: "text", value_text: "sessenta meses") }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_review_decisions_field_same_type_and_tenant/)
    end

    it "rejects an unknown decision and an overlong reason" do
      expect { save_raw(decision: "maybe") }.to raise_error(ActiveRecord::StatementInvalid, /review_decisions_decision_check/)
      expect { save_raw(decision: "rejected", reason: "x" * 1_001) }
        .to raise_error(ActiveRecord::StatementInvalid, /review_decisions_reason_length/)
    end

    it "rejects any UPDATE and DELETE, even bypassing ActiveRecord" do
      decision = with_tenant(tenant) { create(:review_decision, extracted_field: field, reviewed_by: reviewer) }

      expect {
        with_tenant(tenant) { connection.execute("UPDATE review_decisions SET decision = 'rejected' WHERE id = #{connection.quote(decision.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
      expect {
        with_tenant(tenant) { connection.execute("DELETE FROM review_decisions WHERE id = #{connection.quote(decision.id)}") }
      }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it "rejects a decision on another tenant's field" do
      expect {
        with_tenant(tenant) do
          build(:review_decision, extracted_field: other_field, tenant: tenant, reviewed_by: reviewer).save!(validate: false)
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_review_decisions_field_same_type_and_tenant/)
    end
  end
end
