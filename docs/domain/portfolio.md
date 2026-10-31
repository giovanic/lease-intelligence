# Domain: Portfolio (Properties & Counterparties)

Status: **implemented** — models, RLS migrations, policies,
`/api/v1/properties` + `/api/v1/counterparties`, and SPA screens (list,
detail with the record's leases, create/edit, archive/reactivate) in
`apps/web/src/features/portfolio/`. Leases link to both
(`docs/domain/leases.md`).

## Entities

- **Property** (`properties`) — a leased physical location belonging to a
  tenant's portfolio.
  - `name` (required), `code` (optional internal unit code, upper-cased,
    unique per tenant), `property_type` (`retail`, `clinic`, `office`,
    `restaurant`, `gym`, `school`, `warehouse`, `other`).
  - Address: `street`, `city`, `state` (required); `number`, `complement`,
    `district`, `postal_code` (CEP, stored as 8 digits); `country_code`
    (ISO 3166-1 alpha-2, default `BR`; when `BR`, `state` must be a real UF).
  - `area_sqm` — `decimal(12,2)`, optional, > 0; serialized as a string.
  - `status` — `active` / `archived`.
- **Counterparty** (`counterparties`) — the landlord/lessor side of a
  lease: a person or legal entity.
  - `kind` (`individual` / `company`), `legal_name` (required),
    `trade_name`, `email` (lower-cased), `phone`.
  - `tax_id` — optional; digits only; CPF (11, check digits verified) for
    `individual`, CNPJ (14) for `company`; unique per tenant. The database
    enforces the length-by-kind rule, the model the check digits.
  - `status` — `active` / `archived`.

## Relationships

```
Tenant 1---* Property
Tenant 1---* Counterparty
Property 1---* Lease          (leases.property_id)
Counterparty *---* Lease      (through lease_parties, with a role)
```

Both tables have a unique `(id, tenant_id)` index; `leases` and
`lease_parties` reference it with composite foreign keys, so the database
rejects a lease linking another tenant's property or counterparty. An
archived record cannot be newly linked to a lease.

## Isolation and authorization

Both are tenant-owned: `tenant_id` + RLS enabled/forced + isolation
policy (`db/migrate/20261031150000_create_properties.rb`,
`20261031150001_create_counterparties.rb`). Policies inherit
`TenantOwnedPolicy`:

| Action        | owner | admin | manager | analyst | viewer |
|---------------|:-----:|:-----:|:-------:|:-------:|:------:|
| list / show   |  yes  |  yes  |   yes   |   yes   |  yes   |
| create / edit |  yes  |  yes  |   yes   |   no    |   no   |
| delete        |  no   |  no   |   no    |   no    |   no   |

There is no delete: records are archived through `status`, since leases
will reference them and history must be kept. A record of another tenant
answers 404, identical to a nonexistent id.

## API

Contracts are documented on `Api::V1::PropertiesController` and
`Api::V1::CounterpartiesController` and encoded in
`spec/requests/api/v1/{properties,counterparties}_spec.rb`. Collections
are paginated (`page`, `per_page` ≤ 100) and accept `status`, `q`
(and `kind` for counterparties) filters.

## LGPD

A CPF is personal data. `tax_id` and `phone` are filtered from logs
(`config/initializers/filter_parameter_logging.rb`, covered by a request
spec). Deletion/export of an individual counterparty is not built yet —
archiving does not erase personal data.

## Notes

A `Counterparty` is not a `User` — it has no login, no membership. It is
purely a structured record describing who the tenant leases from. Do not
conflate counterparty identity with platform identity.

## Open questions

- Audit trail: creating/editing/archiving these records is not yet
  recorded as an `AuditEvent` (the Audit module does not exist).
- Property-level authorization for the store-manager persona (see
  `docs/domain/identity.md`) — still tenant-level only.
