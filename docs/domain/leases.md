# Domain: Leases & Contract Management

Status: planned domain model. No `Lease`, `Amendment`, or
`ContractualCondition` model exists yet. See ADR-010 (versioning) and
ADR-011 (evidence-first architecture).

## Entities

- **Lease** — the commercial agreement. Belongs to a `Tenant` and a
  `Property`, references one or more `Counterparty` records. Has a
  lifecycle (e.g. draft/active/expired/terminated — exact states TBD).
- **Amendment** — a document that modifies a lease's terms after the
  original contract. References the `Lease` it amends. Never overwrites
  the original contract or prior amendments.
- **ContractualCondition** — the versioned, effective-dated set of approved
  terms for a lease (rent amount, currency, indexation index, renewal
  terms, termination clause, etc.). Each condition set has an effective
  date range; creating a new one (from an approved amendment) does not
  delete the prior one — history must remain queryable ("what were the
  terms on 2024-06-01").

## Relationships

```
Lease 1---* ContractDocument       (original contract, each amendment doc)
Lease 1---* ContractualCondition   (effective-dated history)
Lease 1---* Obligation
```

## Critical date distinctions (do not conflate — `apps/api/CLAUDE.md` §7)

- **Document upload date** — when the file entered the system.
- **Document signature date** — when the parties signed it.
- **Contract effective date** — when its terms legally take effect.
- **Contract commencement date** — when occupancy/use actually begins.
- **Contract expiration date** — when the term ends.

These are frequently different dates on the same document and must be
modeled as distinct columns with correct types (`date`, not `datetime`,
when there is no meaningful time-of-day), not collapsed into one
ambiguous "date" field.

## Lease lifecycle (conceptual, not yet implemented as a state machine)

Draft/negotiation → signed/active → (amendments over time, each producing
new `ContractualCondition` versions) → expiration or termination. Renewal
is itself a business event that should be traceable (did the lease renew
under the original terms, or under amended terms negotiated at renewal
time?).

## Obligation generation

Approved `ContractualCondition`s are the only valid input to obligation
generation (e.g. "notify 90 days before renewal deadline," "readjust rent
annually on contract anniversary"). Obligation generation must never read
directly from unreviewed AI extraction — see
`docs/architecture/document-intelligence.md`.
