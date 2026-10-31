FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    full_name { "Test User" }
    password { "password123!" }
  end
end
