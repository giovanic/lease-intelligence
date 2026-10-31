# ADR-0004: UUID Primary Keys

## Context

Primary key strategy affects ID predictability, multi-tenant safety,
replication/merge scenarios, and API ergonomics.

## Problem

Choose between sequential integer primary keys and UUIDs for all tables.

## Decision

Use UUID primary keys for all tables.

## Alternatives considered

- **Sequential bigint IDs** — rejected as the primary key: predictable,
  enumerable IDs make resource enumeration attacks easier (e.g. guessing
  `/leases/1235` after seeing `/leases/1234`) and are a worse fit for a
  system that may need to merge/import data across environments or
  tenants without collision. Could still be used internally as a
  secondary indexed column if a specific performance need arises, but
  that is not currently justified.
- **UUIDv4 (random)** — viable but has worse index locality than ordered
  UUID variants, which can matter for large, high-insert-rate tables.
- **UUIDv7 (time-ordered)** — preferred specific UUID version when
  implemented: keeps the non-enumerability benefit of UUIDs while
  preserving better index locality (sequential-ish insert pattern) than
  UUIDv4. The exact generation mechanism (Postgres `gen_random_uuid()` vs.
  a Ruby-side UUIDv7 generator) should be decided when the first migration
  is written and recorded as an update to this ADR.

## Consequences

- Positive: IDs are not enumerable, safe to expose in URLs/APIs, merge
  safely across environments.
- Negative: slightly larger index/storage footprint than bigint; requires
  explicit `id: :uuid` configuration in migrations and
  `config.generators.orm = :active_record, primary_key_type: :uuid` (or
  per-migration `id: :uuid`) to be the Rails-wide default — not yet
  configured in `apps/api`.

## Security implications

Reduces resource enumeration risk compared to sequential IDs. Does not by
itself provide tenant isolation — RLS (ADR-0003) remains the control for
that; UUIDs only remove the enumeration/guessing vector.

## Implementation status

**Implemented, with a simplification from the original decision.**
`config.generators.orm = :active_record, primary_key_type: :uuid` is set
in `apps/api/config/application.rb`, and all four Identity & Tenancy
tables use `id: :uuid`. The generation mechanism is Postgres's built-in
`gen_random_uuid()` (core since PostgreSQL 13, no `pgcrypto` extension
needed) — plain **UUIDv4**, not UUIDv7. The index-locality benefit of
UUIDv7 was judged not worth a non-standard ID-generation dependency for
the current table sizes/insert rates; revisit if a specific table's
insert volume makes UUIDv4's random index locality a measured problem.
