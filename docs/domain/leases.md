# Domain: Leases & Contract Management

Status: **lease registration implemented** (API + SPA screens) — `Lease`
and `LeaseParty`. `Amendment` and `ContractualCondition` are still
planned. See ADR-0010 (versioning) and ADR-0011 (evidence-first
architecture).

## Entities

- **Lease** (`leases`, implemented) — the registration record of a
  commercial agreement: which `Property`, under which internal `title`
  (required) and `code` (optional, upper-cased, unique per tenant),
  free-text `notes`, and a lifecycle `status`:
  - `draft` — being registered, not yet in force (default);
  - `active` — in force;
  - `expired` — its term ended;
  - `terminated` — ended early (rescisão/distrato).

  Transitions are free for now (any status → any status); a state
  machine is deferred until conditions/obligations give it real rules.
  **The lease holds no dates, rent or indexation** — those are
  `ContractualCondition`s approved through human review (ADR-0010/0011),
  never typed onto the registration.
- **LeaseParty** (`lease_parties`, implemented) — a `Counterparty`'s
  participation in a lease, with its `role`: `lessor` (locador),
  `guarantor` (fiador) or `intervening_party` (interveniente anuente).
  Each counterparty appears once per lease.
- **Amendment** (planned) — a document that modifies a lease's terms after
  the original contract. References the `Lease` it amends. Never
  overwrites the original contract or prior amendments.
- **ContractualCondition** (planned) — the versioned, effective-dated set
  of approved terms for a lease (rent amount, currency, indexation index,
  renewal terms, termination clause, etc.). Each condition set has an
  effective date range; creating a new one (from an approved amendment)
  does not delete the prior one — history must remain queryable ("what
  were the terms on 2024-06-01").

## Relationships

```
Property 1---* Lease                       (implemented)
Lease 1---* LeaseParty *---1 Counterparty  (implemented)
Lease 1---* ContractDocument               (planned: contract, each amendment doc)
Lease 1---* ContractualCondition           (planned: effective-dated history)
Lease 1---* Obligation                     (planned)
```

`leases` and `lease_parties` reference their parents through composite
foreign keys on `(id, tenant_id)`, so the database rejects a lease or a
party linking records of different tenants. `leases` has its own unique
`(id, tenant_id)` index for the planned child tables.

## Rules (Leases::CreateLease / Leases::UpdateLease)

Enforced in one transaction by `Leases::LeaseWriter`:

- the property and every counterparty are looked up within the current
  tenant (and under RLS) — an id of another tenant is "not found" (422),
  indistinguishable from a nonexistent one;
- at least one `lessor`; each counterparty at most once;
- an archived property or counterparty cannot be newly linked (one already
  linked stays linked);
- the property can only change while the lease is `draft`;
- on update, `parties` (when sent) replaces the whole list; when omitted,
  the parties stay as they are.

There is no delete: a lease ends through its status.

## Isolation and authorization

Both tables are tenant-owned (`tenant_id` + RLS enabled/forced + isolation
policy, `db/migrate/20261031180000_create_leases.rb`,
`20261031180001_create_lease_parties.rb`). `LeasePolicy` inherits
`TenantOwnedPolicy` with the portfolio matrix: every active member reads;
owner/admin/manager create and edit; nobody deletes. A lease of another
tenant answers 404.

## API

`/api/v1/leases` (index/show/create/update) — contract documented on
`Api::V1::LeasesController` and encoded in
`spec/requests/api/v1/leases_spec.rb`. The list is paginated and filters
by `status`, `property_id`, `counterparty_id` and `q` (title/code). The
lease JSON embeds a property summary and, per party, a counterparty
summary **without** `tax_id`/`email`/`phone` (personal data — the full
record is behind `/api/v1/counterparties/:id`).

## Frontend

`apps/web/src/features/leases/`: list (filters in the URL), detail
(parties, and an explicit "no approved conditions yet" state), and a
create/edit form with searchable pickers for the property and each party.
The property and counterparty detail screens list their leases.

## Critical date distinctions (do not conflate — `apps/api/CLAUDE.md` §7)

- **Document upload date** — when the file entered the system.
- **Document signature date** — when the parties signed it.
- **Contract effective date** — when its terms legally take effect.
- **Contract commencement date** — when occupancy/use actually begins.
- **Contract expiration date** — when the term ends.

These are frequently different dates on the same document and must be
modeled as distinct columns with correct types (`date`, not `datetime`,
when there is no meaningful time-of-day), not collapsed into one
ambiguous "date" field. They belong to documents and conditions, not to
the lease registration.

## Lease lifecycle

Draft/negotiation → signed/active → (amendments over time, each producing
new `ContractualCondition` versions) → expiration or termination. Renewal
is itself a business event that should be traceable (did the lease renew
under the original terms, or under amended terms negotiated at renewal
time?). Only the `status` column exists today.

## Obligation generation

Approved `ContractualCondition`s are the only valid input to obligation
generation (e.g. "notify 90 days before renewal deadline," "readjust rent
annually on contract anniversary"). Obligation generation must never read
directly from unreviewed AI extraction — see
`docs/architecture/document-intelligence.md`.

## Open questions

- Audit trail: creating/editing a lease or changing its parties is not
  recorded as an `AuditEvent` yet (the Audit module does not exist), and
  a replaced party list keeps no history.
- Status transitions are unrestricted (e.g. `terminated` → `draft`).
