# Domain: Contract Intelligence (OCR/AI/Evidence/Review)

Status: planned domain model. The first pipeline step — text extraction
with the OCR provider abstraction (`DocumentTextExtraction`,
`DocumentTextPage`, ADR-0016, see `docs/domain/documents.md`) — is
implemented; `ExtractionRun` and everything after it is not. See ADR-008,
ADR-009, ADR-011, ADR-012, ADR-0016.

## Entities

- **ExtractionRun** — one execution of the OCR/AI pipeline against a
  `DocumentVersion`. Records provider, model, model version, prompt
  version, status (pending/running/succeeded/failed), token usage/cost
  where available, execution time, error detail, output version.
- **ExtractedField** — one structured value produced by an `ExtractionRun`
  (e.g. field name `monthly_rent`, value `12000.00`, currency `BRL`).
  Immutable once created.
- **EvidenceReference** — links an `ExtractedField` to its source location
  (document version, page number, text span/snippet, optionally a bounding
  box if OCR coordinates are available).
- **ReviewDecision** — a human's action on an `ExtractedField`: approve,
  edit-then-approve (with the corrected value recorded on the decision,
  not on the original field), or reject (with optional reason).

## Relationships

```
DocumentVersion 1---* ExtractionRun
ExtractionRun 1---* ExtractedField
ExtractedField 1---* EvidenceReference
ExtractedField 1---* ReviewDecision
```

## Non-negotiable rules (restated from `apps/api/CLAUDE.md` §8/§14)

- An `ExtractedField` is never mutated after creation — corrections always
  create a new `ReviewDecision`.
- A field with zero `EvidenceReference`s should not pass schema validation
  — the reviewer must always be able to see where a value came from.
- Model confidence scores (if a provider returns them) are not a
  calibrated probability and must not drive automatic approval without
  validation against an annotated dataset.
- Only an approved `ReviewDecision` feeds into `ContractualCondition`
  materialization (`docs/domain/leases.md`). Nothing downstream reads raw
  `ExtractedField`s directly.

## Provider abstraction

Both OCR and LLM access go through internal interfaces
(`docs/architecture/document-intelligence.md`, ADR-008/ADR-009) so a
vendor can be swapped (e.g. different OCR vendor, different LLM vendor)
without changing `ExtractionRun`/`ExtractedField` domain logic.
