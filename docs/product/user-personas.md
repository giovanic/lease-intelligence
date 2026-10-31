# User Personas

Status: planned personas, used to drive UX and permission design. Role
names here are conceptual — no `role` enum/permission model exists in code
yet; see `docs/domain/identity.md` for the planned membership/role shape.

## Portfolio Manager (primary persona)

Works for the tenant organization, owns the real-estate portfolio across
many units. Needs: a reliable view of every lease's current terms, upcoming
renewal/readjustment deadlines, and the ability to compare terms across
properties. Pain today: spreadsheets built by hand from PDFs, frequently
stale.

## Legal / Contracts Analyst

Reviews uploaded contracts and amendments, validates AI-extracted fields
against the source document, approves or corrects them. Needs: side-by-side
document viewer and extracted-field editor, full evidence trail, ability to
reject an extraction and flag it for reprocessing.

## Finance / FP&A Analyst

Consumes approved contractual facts (rent, indexation index, charges) for
budgeting and cost analysis. Needs: confidence that any number they see has
been human-approved, not raw AI output; historical view of condition changes
over time (e.g., rent before/after a readjustment).

## Tenant Administrator

Manages organization membership: invites users, assigns roles, oversees
subscription/tenant settings. Needs: clear visibility into who has access to
what, audit log of sensitive actions.

## Operations / Store Manager (secondary persona, later phase)

Local manager of a single property (e.g., one restaurant unit). Needs a
narrow view limited to their property's lease and obligations — relevant to
future fine-grained, property-level authorization, not just tenant-level.

## Platform Super-Admin (internal, Lease Intelligence staff)

Operates the platform across tenants for support/debugging. Any
cross-tenant access by this persona must be explicit, audited, and never a
default code path — see `apps/api/CLAUDE.md` §9 and ADR-002.
