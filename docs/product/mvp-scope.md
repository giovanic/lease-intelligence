# MVP Scope

Status: planned scope. Nothing below is implemented yet.

## In scope for MVP

- **Organization Management** — a tenant (organization) with basic profile.
- **User Management & Memberships** — global user identities, membership
  into one or more tenants, role-based permission within a tenant.
- **Portfolio & Property Management** — register properties belonging to a
  tenant (address, type, area).
- **Counterparty Management** — landlords/lessors as structured records.
- **Lease Management** — a lease tied to a tenant, a property, and
  counterparties.
- **Document Management & Versioning** — upload original contract/amendment
  files, store immutably, version explicitly.
- **OCR Processing** — extract text from scanned/PDF documents when native
  text extraction is insufficient.
- **AI Contract Intelligence** — structured extraction of key fields
  (parties, dates, rent, indexation, renewal terms) from document text.
- **Evidence Management** — every extracted field links back to its source
  document/page/text span.
- **Human Review** — reviewer approves, edits, or rejects each extracted
  field before it becomes an approved contractual fact.
- **Amendment Management** — amendments reference the original lease and
  produce new effective-dated conditions without overwriting history.
- **Contractual Conditions** — the "current approved terms" view, with
  effective-date history.
- **Lease Obligations & Calendar** — recurring/one-off obligations (e.g.
  renewal notice deadline, readjustment date) surfaced on a calendar.
- **Notifications** — alerts for upcoming obligations/deadlines.
- **Audit Trail** — who did what, when, to which tenant-owned record.
- **Dashboard** — portfolio-level overview (lease count, upcoming
  deadlines, documents pending review).

## Explicitly out of scope for MVP

- Full lease accounting (CPC 06 / IFRS 16) treatment.
- Automated legal opinions or legal risk scoring presented as authoritative.
- Automated payments or payment reconciliation.
- Electronic signature collection/workflow.
- Advanced ERP integrations.
- Native mobile applications.
- Any autonomous legal or financial decision made by the system without a
  human approving it first.

## MVP acceptance bar

A tenant admin can: invite a user, register a property, register a
counterparty, create a lease, upload the signed contract, have it OCR'd and
AI-extracted, review and approve the extracted fields, see the lease's
current conditions and upcoming obligations on a calendar, and confirm that
a user from a different tenant cannot see any of it. Every approved field
must be traceable to its source evidence.
