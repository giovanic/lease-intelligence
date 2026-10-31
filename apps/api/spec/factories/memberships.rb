# Creating a Membership goes through RLS like any other write (FORCE ROW
# LEVEL SECURITY) — callers must invoke this factory from inside
# `with_tenant(tenant) { create(:membership, tenant: tenant, ...) }`, not
# bare, or the insert will be denied exactly as it would be in production.
FactoryBot.define do
  factory :membership do
    tenant
    user
    role { "owner" }
    status { "active" }
  end
end
