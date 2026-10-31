# Inserts go through RLS like any other write — call these factories inside
# `with_tenant(tenant) { create(:lease, tenant: tenant) }`. The property
# and counterparties are created in the lease's own tenant (the composite
# foreign keys reject anything else).
#
# A bare :lease has no parties (the "at least one lessor" rule lives in
# Leases::CreateLease/UpdateLease); use :with_lessor for a realistic one.
FactoryBot.define do
  factory :lease do
    tenant
    property { association :property, tenant: tenant }
    sequence(:title) { |n| "Contrato de locação #{n}" }
    status { "active" }

    trait :with_lessor do
      after(:create) do |lease|
        create(:lease_party, lease: lease, role: "lessor")
        lease.lease_parties.reload # loaded inside the caller's tenant context
      end
    end
  end

  factory :lease_party do
    lease
    tenant { lease.tenant }
    counterparty { association :counterparty, tenant: tenant }
    role { "lessor" }
  end
end
