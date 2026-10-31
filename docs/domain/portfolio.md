# Domain: Portfolio (Properties & Counterparties)

Status: planned domain model. No `Property` or `Counterparty` model exists
yet.

## Entities

- **Property** — a leased physical location belonging to a tenant's
  portfolio. Attributes (planned): address, type (e.g. retail, clinic,
  office), area (m²), tenant_id.
- **Counterparty** — the landlord/lessor side of a lease: a person or legal
  entity. Attributes (planned): legal name, tax ID (CPF/CNPJ for Brazil),
  contact info, tenant_id.

## Relationships

```
Tenant 1---* Property
Tenant 1---* Counterparty
Property 1---* Lease
Counterparty *---* Lease   (a lease may have more than one counterparty;
                             a counterparty may appear on many leases)
```

Both `Property` and `Counterparty` are tenant-owned records subject to RLS
and must never be creatable/readable cross-tenant.

## Notes

A `Counterparty` is not a `User` — it has no login, no membership. It is
purely a structured record describing who the tenant leases from. Do not
conflate counterparty identity with platform identity.
