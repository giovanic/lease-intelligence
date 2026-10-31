# ADR-0012: Human-in-the-Loop Review

## Context

AI extraction of contractual terms will sometimes be wrong, and the
consequences of acting on a wrong rent value, wrong renewal date, or wrong
termination clause are real financial/legal consequences for the customer.

## Problem

Decide how AI output becomes trusted business data, and ensure the system
never silently promotes unreviewed AI output into a decision-driving fact.

## Decision

No `ExtractedField` becomes part of a lease's `ContractualCondition`s
without a human `ReviewDecision` (approve, or edit-then-approve). Rejected
or unreviewed fields never reach obligation generation, dashboards, or any
other consumer that treats data as fact. This is enforced as a structural
boundary (downstream consumers read only approved facts), not merely a UI
convention that could be bypassed by a different code path.

## Alternatives considered

- **Auto-approve above a confidence threshold** — rejected: LLM-reported
  confidence (where available at all) is not a calibrated probability
  (root `CLAUDE.md` §14); using it as an auto-approval gate would
  eventually auto-approve a wrong, consequential value with no human ever
  looking at it.
- **Review as an optional, skippable step** — rejected: optional review
  means the default path under time pressure becomes "skip it," which
  defeats the purpose for exactly the fields that matter most.
- **Review only for a subset of "critical" fields, auto-approve the
  rest** — plausible future refinement (e.g. auto-approving clearly
  low-stakes metadata), but not adopted now; if pursued later, the set of
  fields eligible for auto-approval must be an explicit, reviewed list,
  not a default.

## Consequences

- Positive: the product's core trust claim ("reliability of contractual
  information matters more than how much the AI can extract," root
  `CLAUDE.md` §18) is backed by an actual structural control, not a
  promise.
- Negative: review is a real workflow cost — every document requires human
  attention before its terms are "live." The product must make that review
  experience efficient (side-by-side viewer, evidence-linked editing) to
  keep this sustainable, which is why that UX requirement is called out
  explicitly in `apps/api/CLAUDE.md` §12.

## Security implications

This is as much a business-integrity control as a security control: it
prevents an adversarial or malformed document (including one engineered to
manipulate the LLM, i.e. prompt injection) from directly becoming a
financial/legal fact in the system without a human catching it.

## Implementation status

**Decided, not implemented.** No `ReviewDecision` model, no review queue,
and no enforcement boundary between extracted and approved data exist
yet.
