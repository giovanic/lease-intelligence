# Glossary

- **Tenant** — an organization (customer account) in the multi-tenant
  system. All business data belongs to exactly one tenant.
- **User** — a global identity that may hold memberships in multiple
  tenants.
- **Membership** — the join between a `User` and a `Tenant`, carrying role
  and access permissions within that tenant.
- **Property** — a leased physical location belonging to a tenant's
  portfolio.
- **Counterparty** — the landlord/lessor (person or legal entity) on the
  other side of a lease.
- **Lease** — the commercial agreement between the tenant and a
  counterparty for a property.
- **Contract Document** — the conceptual document entity for a lease (e.g.,
  "the original contract," "amendment #2").
- **Document Version** — an immutable, versioned file artifact of a
  Contract Document. Originals are never overwritten; new versions are
  appended.
- **Extraction Run** — one execution of the AI/OCR pipeline against a
  specific Document Version, recording provider, model, prompt version,
  status, cost, and timing.
- **Extracted Field** — a single structured value produced by an Extraction
  Run (e.g., "monthly rent = 12,000 BRL"), immutable once produced.
- **Evidence Reference** — a pointer from an Extracted Field back to the
  exact source location (document, page, text span/snippet) it came from.
- **Review Decision** — a human's approve/edit/reject action on an
  Extracted Field. Does not mutate the original extraction; it is a new
  record.
- **Approved Contractual Fact** — the current, human-approved value for a
  contractual field, derived from a Review Decision.
- **Contractual Condition** — the set of approved facts valid for a lease
  during a given effective-date range (supports history across amendments).
- **Amendment** — a document that modifies a lease's terms after the
  original contract; produces new effective-dated Contractual Conditions
  without deleting prior ones.
- **Obligation** — a tracked duty or deadline derived from a lease's
  conditions (e.g., renewal notice, readjustment date, payment date).
- **Calendar Event** — the user-facing scheduling representation of an
  Obligation.
- **Audit Event** — an immutable record of a sensitive action taken by a
  user or the system against tenant-owned data.
- **RLS** — PostgreSQL Row-Level Security; the database-enforced mechanism
  preventing cross-tenant row access regardless of application-layer bugs.
