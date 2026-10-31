# ADR-0001: Modular Monolith

## Context

Lease Intelligence has ~12+ conceptual domains (identity, tenancy,
portfolio, leases, documents, contract intelligence, review, obligations,
calendar, notifications, audit, integrations). The team is small and the
product is pre-MVP.

## Problem

How should domain boundaries be enforced in code without the operational
cost of microservices, while still avoiding a single undifferentiated
"big ball of mud" Rails app?

## Decision

Build a single Rails application (`apps/api`) organized as a modular
monolith: explicit domain boundaries expressed through namespacing
(services, policies, models grouped by domain) rather than through
separate deployable services or one Rails Engine per domain.

## Alternatives considered

- **Microservices per domain** — rejected for now: massively higher
  operational complexity (deployment, networking, distributed
  transactions, observability) for a pre-MVP product with a small team.
  Revisit only if a specific domain demonstrably needs independent
  scaling/deployment.
- **One Rails Engine per domain** — rejected: engines add packaging
  overhead (routing, isolated namespaces, versioning) disproportionate to
  the benefit at this stage; explicit folder/namespace boundaries give
  most of the organizational benefit without the overhead.
- **Undifferentiated monolith (default Rails MVC with no domain
  structure)** — rejected: at 12+ domains this reliably degenerates into
  tangled cross-domain dependencies and god models/controllers.

## Consequences

- Positive: single deploy unit, single database, simple transactions
  across domains when genuinely needed, lower operational overhead.
- Negative: requires discipline — nothing stops a developer from reaching
  across a domain boundary directly; this must be caught in code review
  and by the `software-architect` agent, not enforced by a hard runtime
  boundary.
- Future extraction of a domain into its own service remains possible if
  boundaries are kept clean now.

## Security implications

None directly from this choice, but domain boundaries make it easier to
reason about where tenant-scoping and authorization must be enforced
(each domain's entry points are the enforcement points).

## Implementation status

**Decided, not implemented.** No domain namespacing exists yet in
`apps/api/app`. The first domain implementation should establish the
concrete namespacing convention and this ADR should be updated with the
actual chosen pattern (e.g. `app/domains/<name>/...` vs. prefixed module
names).
