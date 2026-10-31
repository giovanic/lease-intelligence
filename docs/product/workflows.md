# Main Workflows

Status: planned workflows, to guide domain and API design. Not implemented.

## 1. Onboard a tenant and invite users

Tenant admin signs up → tenant record created → admin becomes first
membership → admin invites additional users by email → invited users accept
and create/attach a global `User` identity → membership created with a role.

## 2. Register portfolio data

Admin/manager registers properties (address, type, area) and counterparties
(landlord legal entity/person). These are prerequisites for creating a
lease.

## 3. Create a lease and upload the originating contract

Manager creates a `Lease` linking tenant + property + counterparties →
uploads the signed contract file → file is checksummed and stored privately
→ a `DocumentVersion` is created → async pipeline is enqueued (see
`docs/architecture/document-intelligence.md`).

## 4. Document intelligence pipeline (async)

Upload → validation → checksum → private storage → text extraction → OCR
(if needed) → page normalization → classification → structured AI
extraction → schema validation → evidence validation → queued for human
review. Each step's status is visible to the user; failures are retryable
and never silently swallowed.

## 5. Human review of extracted fields

Analyst opens the review queue, sees document side-by-side with extracted
fields and their evidence (page/snippet). For each field: approve, edit then
approve, or reject. Only approved fields become part of the lease's
contractual conditions. Rejected/edited fields never overwrite the original
AI output — the raw extraction is preserved immutably, with a new review
decision recorded.

## 6. Amendment workflow

User uploads an amendment document against an existing lease → pipeline
runs → extracted changes are proposed as a diff against current approved
conditions → analyst reviews and approves → a new `ContractualCondition`
version is created with an effective date, without deleting prior history.

## 7. Obligation tracking and calendar

Approved conditions (e.g., renewal notice period, readjustment anniversary)
generate `Obligation` records with due dates → obligations surface on a
calendar view → notifications fire ahead of due dates.

## 8. Cross-tenant security check (continuous, not user-facing)

Every tenant-scoped request must be provable, in tests, to deny access to
another tenant's data — this is a workflow for engineering, not end users,
but it gates every feature above. See `.claude/rules/multi-tenancy.md` and
`.claude/agents/security-engineer.md`.
