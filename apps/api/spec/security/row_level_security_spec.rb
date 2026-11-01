require "rails_helper"

# The raw-SQL-level layer of the three-layer tenant isolation test
# described in docs/runbooks/testing.md: this proves PostgreSQL itself
# refuses cross-tenant rows for the role the application actually
# connects as (lease_intelligence — non-superuser, no BYPASSRLS, see
# config/database.yml), independent of any ActiveRecord/Rails-level
# authorization. The policy and request layers live in spec/policies
# and spec/requests; this file is the database-level proof.
RSpec.describe "Row-Level Security", type: :model do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  describe "memberships" do
    it "denies an insert with no tenant context" do
      membership = build(:membership, tenant: tenant_a, user: user_a)
      expect { membership.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "denies an insert whose tenant_id does not match the active tenant context" do
      # The raise must propagate out of `with_tenant` itself so its
      # `requires_new: true` savepoint rolls back cleanly on the way out
      # (see TenantContext's comment) — rescuing it inside would leave
      # that subtransaction aborted for whatever runs next.
      expect {
        with_tenant(tenant_a, user: user_a) do
          mismatched = build(:membership, tenant: tenant_b, user: user_a)
          mismatched.save!(validate: false)
        end
      }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "only returns the active tenant's rows when both tenants have memberships" do
      membership_a = with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }
      membership_b = with_tenant(tenant_b, user: user_b) { create(:membership, tenant: tenant_b, user: user_b) }

      with_tenant(tenant_a, user: user_a) do
        visible = Membership.pluck(:id)
        expect(visible).to contain_exactly(membership_a.id)
        expect(visible).not_to include(membership_b.id)
      end
    end

    it "lets a user see their own membership rows with no active tenant context (bootstrap)" do
      membership_a = with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }
      with_tenant(tenant_b, user: user_b) { create(:membership, tenant: tenant_b, user: user_b) }

      with_user_only(user_a) do
        visible = Membership.pluck(:id)
        expect(visible).to eq([ membership_a.id ])
      end
    end

    it "returns nothing at all with neither tenant nor user context" do
      with_tenant(tenant_a, user: user_a) { create(:membership, tenant: tenant_a, user: user_a) }

      expect(Membership.count).to eq(0)
    end
  end

  describe "invitations" do
    it "denies an insert with no tenant context" do
      invitation = build(:invitation, tenant: tenant_a, invited_by: user_a)
      expect { invitation.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "only returns the active tenant's invitations" do
      invitation_a = with_tenant(tenant_a, user: user_a) { create(:invitation, tenant: tenant_a, invited_by: user_a) }
      invitation_b = with_tenant(tenant_b, user: user_b) { create(:invitation, tenant: tenant_b, invited_by: user_b) }

      with_tenant(tenant_a, user: user_a) do
        visible = Invitation.pluck(:id)
        expect(visible).to contain_exactly(invitation_a.id)
        expect(visible).not_to include(invitation_b.id)
      end
    end
  end
  # Portfolio tables, exercised with raw SQL only — no model, no policy —
  # so the proof rests on PostgreSQL alone.
  {
    "properties" => {
      factory: :property,
      insert_columns: "tenant_id, name, property_type, street, city, state, created_at, updated_at",
      insert_values: "'Unidade X', 'retail', 'Rua A', 'Recife', 'PE', now(), now()",
      update_set: "name = 'hijacked'"
    },
    "counterparties" => {
      factory: :counterparty,
      insert_columns: "tenant_id, kind, legal_name, created_at, updated_at",
      insert_values: "'company', 'Locadora X', now(), now()",
      update_set: "legal_name = 'hijacked'"
    },
    # Random parent ids: the RLS check runs before the foreign keys, so the
    # error proven here is the policy's, not a missing parent.
    "leases" => {
      factory: :lease,
      insert_columns: "tenant_id, property_id, title, status, created_at, updated_at",
      insert_values: "gen_random_uuid(), 'Contrato X', 'draft', now(), now()",
      update_set: "title = 'hijacked'"
    },
    "lease_parties" => {
      factory: :lease_party,
      # A party's lease, counterparty and own row must share one tenant.
      create: ->(tenant) { create(:lease_party, lease: create(:lease, tenant: tenant)) },
      insert_columns: "tenant_id, lease_id, counterparty_id, role, created_at, updated_at",
      insert_values: "gen_random_uuid(), gen_random_uuid(), 'lessor', now(), now()",
      update_set: "role = 'guarantor'"
    },
    "contract_documents" => {
      factory: :contract_document,
      insert_columns: "tenant_id, lease_id, kind, title, created_at, updated_at",
      insert_values: "gen_random_uuid(), 'amendment', 'Aditivo X', now(), now()",
      update_set: "title = 'hijacked'"
    },
    "document_versions" => {
      factory: :document_version,
      create: ->(tenant) { create(:document_version, contract_document: create(:contract_document, tenant: tenant)) },
      insert_columns: "tenant_id, contract_document_id, version_number, storage_key, original_filename, " \
        "content_type, byte_size, sha256, uploaded_by_id, created_at",
      insert_values: "gen_random_uuid(), 1, gen_random_uuid()::text, 'x.pdf', 'application/pdf', 10, " \
        "encode(sha256(gen_random_uuid()::text::bytea), 'hex'), gen_random_uuid(), now()",
      update_set: "original_filename = 'hijacked.pdf'",
      # Versions are immutable: the BEFORE UPDATE trigger rejects the move
      # even before the RLS WITH CHECK would.
      move_error: /row-level security|document_versions rows are immutable/
    },
    "document_text_extractions" => {
      factory: :document_text_extraction,
      create: ->(tenant) { create(:document_text_extraction, document_version: create_version(tenant)) },
      insert_columns: "tenant_id, document_version_id, status, created_at, updated_at",
      insert_values: "gen_random_uuid(), 'pending', now(), now()",
      update_set: "status = 'running'"
    },
    "document_text_pages" => {
      factory: :document_text_page,
      create: ->(tenant) { create(:document_text_page, text_extraction: create(:document_text_extraction, document_version: create_version(tenant))) },
      insert_columns: "tenant_id, text_extraction_id, page_number, source, text, created_at",
      insert_values: "gen_random_uuid(), 1, 'ocr', 'texto', now()",
      update_set: "text = 'hijacked'",
      # Pages are immutable: the trigger rejects the move as well.
      move_error: /row-level security|document_text_pages rows are immutable/
    },
    "extraction_runs" => {
      factory: :extraction_run,
      create: ->(tenant) { create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: create_version(tenant))) },
      insert_columns: "tenant_id, document_version_id, text_extraction_id, status, provider, model, prompt_version, " \
        "effort, created_at, updated_at",
      insert_values: "gen_random_uuid(), gen_random_uuid(), 'pending', 'anthropic', 'm', 'v1', 'high', now(), now()",
      update_set: "status = 'running'"
    },
    "extracted_fields" => {
      factory: :extracted_field,
      create: ->(tenant) { create(:extracted_field, extraction_run: create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: create_version(tenant)))) },
      insert_columns: "tenant_id, extraction_run_id, position, field_key, value_type, value_integer, created_at",
      insert_values: "gen_random_uuid(), 0, 'term_months', 'integer', 12, now()",
      update_set: "value_integer = 99",
      # AI output is immutable: the trigger rejects the move as well.
      move_error: /row-level security|extracted_fields rows are immutable/
    },
    "evidence_references" => {
      factory: :evidence_reference,
      create: ->(tenant) { create(:evidence_reference, extracted_field: create(:extracted_field, extraction_run: create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: create_version(tenant))))) },
      insert_columns: "tenant_id, extracted_field_id, text_page_id, page_number, start_offset, end_offset, created_at",
      insert_values: "gen_random_uuid(), gen_random_uuid(), 1, 0, 5, now()",
      update_set: "start_offset = 1",
      move_error: /row-level security|evidence_references rows are immutable/
    },
    "review_decisions" => {
      factory: :review_decision,
      create: ->(tenant) { create(:review_decision, extracted_field: create(:extracted_field, extraction_run: create(:extraction_run, text_extraction: create(:document_text_extraction, document_version: create_version(tenant))))) },
      insert_columns: "tenant_id, extracted_field_id, value_type, decision, reviewed_by_id, created_at",
      insert_values: "gen_random_uuid(), 'integer', 'approved', gen_random_uuid(), now()",
      update_set: "decision = 'rejected'",
      move_error: /row-level security|review_decisions rows are immutable/
    }
  }.each do |table, config|
    describe "#{table} (raw SQL)" do
      let(:connection) { ActiveRecord::Base.connection }
      let!(:row_b) { with_tenant(tenant_b) { create_row(config, tenant_b) } }

      def create_version(tenant)
        create(:document_version, contract_document: create(:contract_document, tenant: tenant))
      end

      def create_row(config, tenant)
        config[:create] ? instance_exec(tenant, &config[:create]) : create(config[:factory], tenant: tenant)
      end

      def insert_sql(table, config, tenant_id)
        "INSERT INTO #{table} (#{config[:insert_columns]}) " \
          "VALUES (#{connection.quote(tenant_id)}, #{config[:insert_values]})"
      end

      it "hides another tenant's row from SELECT" do
        with_tenant(tenant_a) do
          expect(connection.select_value("SELECT count(*) FROM #{table} WHERE id = #{connection.quote(row_b.id)}")).to eq(0)
        end
      end

      it "returns no rows at all without tenant context" do
        expect(connection.select_value("SELECT count(*) FROM #{table}")).to eq(0)
      end

      it "makes UPDATE and DELETE of another tenant's row affect nothing" do
        with_tenant(tenant_a) do
          updated = connection.exec_update("UPDATE #{table} SET #{config[:update_set]} WHERE id = #{connection.quote(row_b.id)}")
          deleted = connection.exec_delete("DELETE FROM #{table} WHERE id = #{connection.quote(row_b.id)}")

          expect([ updated, deleted ]).to eq([ 0, 0 ])
        end
        with_tenant(tenant_b) { expect(connection.select_value("SELECT count(*) FROM #{table}")).to eq(1) }
      end

      it "denies inserting a row for another tenant" do
        expect {
          with_tenant(tenant_a) { connection.execute(insert_sql(table, config, tenant_b.id)) }
        }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end

      it "denies inserting with no tenant context" do
        expect { connection.execute(insert_sql(table, config, tenant_a.id)) }
          .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end

      it "denies moving an own row to another tenant" do
        row_a = with_tenant(tenant_a) { create_row(config, tenant_a) }

        expect {
          with_tenant(tenant_a) do
            connection.execute(
              "UPDATE #{table} SET tenant_id = #{connection.quote(tenant_b.id)} WHERE id = #{connection.quote(row_a.id)}"
            )
          end
        }.to raise_error(ActiveRecord::StatementInvalid, config.fetch(:move_error, /row-level security/))
      end
    end
  end
end
