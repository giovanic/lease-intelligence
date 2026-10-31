# Same RLS note as spec/factories/memberships.rb — create from inside
# `with_tenant(tenant) { ... }`.
FactoryBot.define do
  factory :invitation do
    tenant
    invited_by factory: :user
    sequence(:email) { |n| "invitee#{n}@example.com" }
    role { "viewer" }
    status { "pending" }
    expires_at { 7.days.from_now }
  end
end
