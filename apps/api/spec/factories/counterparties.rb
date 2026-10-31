# Inserts go through RLS like any other write — call this factory inside
# `with_tenant(tenant) { create(:counterparty, tenant: tenant) }`.
FactoryBot.define do
  factory :counterparty do
    tenant
    kind { "company" }
    sequence(:legal_name) { |n| "Imobiliária Exemplo #{n} Ltda" }
    sequence(:tax_id) { |n| BrazilianTaxIdGenerator.cnpj(n) }
    email { "contato@example.com" }

    trait :individual do
      kind { "individual" }
      sequence(:legal_name) { |n| "Locador Pessoa Física #{n}" }
      sequence(:tax_id) { |n| BrazilianTaxIdGenerator.cpf(n + 100) }
    end
  end
end
