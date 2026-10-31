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
    }
  }.each do |table, config|
    describe "#{table} (raw SQL)" do
      let(:connection) { ActiveRecord::Base.connection }
      let!(:row_b) { with_tenant(tenant_b) { create(config[:factory], tenant: tenant_b) } }

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
        row_a = with_tenant(tenant_a) { create(config[:factory], tenant: tenant_a) }

        expect {
          with_tenant(tenant_a) do
            connection.execute(
              "UPDATE #{table} SET tenant_id = #{connection.quote(tenant_b.id)} WHERE id = #{connection.quote(row_a.id)}"
            )
          end
        }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
    end
  end
end
