# Inserts go through RLS like any other write — call this factory inside
# `with_tenant(tenant) { create(:property, tenant: tenant) }`.
FactoryBot.define do
  factory :property do
    tenant
    sequence(:name) { |n| "Unidade #{n}" }
    property_type { "clinic" }
    street { "Avenida Paulista" }
    number { "1000" }
    district { "Bela Vista" }
    city { "São Paulo" }
    state { "SP" }
    postal_code { "01310100" }
    country_code { "BR" }
    area_sqm { BigDecimal("152.37") }
  end
end
