# Domain: Documents

Status: planned domain model. No `ContractDocument`, `DocumentVersion`, or
storage integration exists yet.

## Entities

- **ContractDocument** — the conceptual document slot for a lease (e.g.
  "the original contract," "amendment #2"). Belongs to a `Lease`.
- **DocumentVersion** — an immutable, versioned file artifact of a
  `ContractDocument`. Stores file reference (Active Storage), SHA-256
  checksum, content type, page count (once known), uploader, upload
  timestamp.

## Relationships

```
Lease 1---* ContractDocument
ContractDocument 1---* DocumentVersion
DocumentVersion 1---* ExtractionRun
```

## Rules

- A `DocumentVersion`'s underlying file is never overwritten or mutated
  after creation. A "correction" is a new `DocumentVersion`.
- Files are stored privately (ADR-007); access always goes through
  authorization + short-lived signed URLs, never a permanent public link.
- SHA-256 checksum is computed at upload time, both to detect accidental
  duplicate uploads and to support integrity verification later.
- A `DocumentVersion` is the unit that an `ExtractionRun` operates on — an
  extraction always references exactly one document version, so results
  stay traceable to the exact file bytes that produced them.
