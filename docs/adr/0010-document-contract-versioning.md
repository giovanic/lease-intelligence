# ADR-0010: Document and Contract Versioning

## Context

Contracts are amended over time. The original signed document must remain
intact and legally unambiguous, while the business needs a current view
of "what are the terms right now" and a historical view of "what were the
terms on date X."

## Problem

Model document immutability and contractual condition history without
losing the ability to query "current terms" efficiently.

## Decision

Two separate versioning mechanisms, deliberately not conflated:

1. **Document versioning** — `ContractDocument` has many immutable
   `DocumentVersion`s (append-only; originals are never overwritten).
2. **Contractual condition versioning** — a `Lease` has many
   effective-dated `ContractualCondition` records; a new amendment
   produces a new condition record with an effective date, never mutating
   a prior one.

## Alternatives considered

- **Single mutable "current terms" row, updated in place on amendment** —
  rejected: destroys historical traceability ("what were the terms before
  this amendment") which the product explicitly requires.
- **Event-sourcing the entire lease as a stream of events, deriving state
  on read** — more powerful but a significantly larger architectural
  investment than justified for MVP; revisit only if the effective-dated
  snapshot model proves insufficient.
- **Versioning documents and conditions as one combined concept** —
  rejected: a document version (a PDF file) and a contractual condition
  (a structured, approved fact set) have different lifecycles — one
  document can yield many reviewed/approved condition changes, and a
  condition's provenance needs to point to the specific document version
  it came from, which requires them to be distinct, linked entities.

## Consequences

- Positive: "current terms" is a simple query (latest effective
  condition), "historical terms as of date X" is also a simple query
  (condition effective at that date), and the original documents remain
  an untouched legal record.
- Negative: requires careful query design to always select the right
  effective condition (off-by-one date bugs are an easy mistake); requires
  discipline to never "fix" a condition record in place instead of
  creating a new effective-dated one.

## Security implications

None directly, but this model is what makes audit and evidence-first
guarantees (ADR-0011) possible — without it, "what did we know and when"
could not be answered reliably, which matters for both customer trust and
potential legal/compliance inquiries.

## Implementation status

**Decided, not implemented.** No `ContractDocument`, `DocumentVersion`, or
`ContractualCondition` models exist yet.
