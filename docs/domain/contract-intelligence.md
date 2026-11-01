# Domain: Contract Intelligence (OCR/AI/Evidence/Review)

Status: **extraction and evidence implemented** (`feat/ai-contract-extraction`,
ADR-0017): text extraction (`DocumentTextExtraction`, `DocumentTextPage`,
ADR-0016, see `docs/domain/documents.md`), then `ExtractionRun`,
`ExtractedField` and `EvidenceReference`, API + the "Campos (IA)" column
of the lease's documents. `ReviewDecision` (human review) is **not built**
— every field is an unreviewed AI candidate. See ADR-008, ADR-009,
ADR-011, ADR-012, ADR-0016, ADR-0017.

## Entities

- **ExtractionRun** (`extraction_runs`, implemented) — one execution of the
  AI extraction against a `DocumentVersion`, reading one exact
  `DocumentTextExtraction`. Records provider, model, model version, prompt
  version, status (pending/running/succeeded/failed), token usage/cost
  where available, execution time, error detail, output version.
- **ExtractedField** (`extracted_fields`, implemented) — one structured
  value produced by an `ExtractionRun` (e.g. field name `monthly_rent`,
  value `12000.00`, currency `BRL`), with one typed column per kind of
  value (`date`, `integer`, `money` = `numeric(15,2)` + currency, `option`,
  `text`, `party` = name + optional CPF/CNPJ). Immutable once created
  (trigger). The field set is `FieldExtraction::Catalog` (`lease-fields-v1`,
  17 fields — ADR-0017).
- **EvidenceReference** (`evidence_references`, implemented) — links an
  `ExtractedField` to its source: the `DocumentTextPage` and the character
  span `[start_offset, end_offset)` of the quote in that page's stored text
  (the snippet is sliced from the page when served). No bounding boxes
  (Tesseract's coordinates are not stored). Immutable once created.
- **ReviewDecision** (planned, next phase) — a human's action on an `ExtractedField`: approve,
  edit-then-approve (with the corrected value recorded on the decision,
  not on the original field), or reject (with optional reason).

## Relationships

```
DocumentVersion 1---* ExtractionRun *---1 DocumentTextExtraction
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

## Implementation (ADR-0017)

- Flow: `ExtractDocumentTextJob` (text succeeded) →
  `FieldExtraction::RequestRun` → `ExtractContractFieldsJob` (queue
  `documents`): `StartRun` (load pages) → `ExtractFields` (prompt +
  provider + `ValidateOutput`, outside any transaction) → `RecordOutcome`
  (fields + evidence + usage in one transaction). At most one
  pending/running run per version; stuck runs close as `abandoned` after
  an hour. Expected provider failures are recorded with an `error_code`
  (`ExtractionRun::ERROR_CODES`), not retried.
- Needs a provider for the deployment (`LLM_PROVIDER=ollama` — local,
  free — or `anthropic` with its key; none: the manual request answers
  503) **and** the organization's consent (`tenants.ai_extraction_enabled`,
  off by default; off: nothing is requested and the manual request answers
  422 `extraction_disabled`; a queued run fails `ai_disabled`) — ADR-0018.
- API: `POST /api/v1/document_versions/:id/extraction_runs`
  (owner/admin/manager), `GET /api/v1/extraction_runs/:id` (any active
  member), `extraction_run` summary on the version JSON — contract on
  `Api::V1::ExtractionRunsController`, encoded in
  `spec/requests/api/v1/extraction_runs_spec.rb`.
- Isolation: the three tables are tenant-owned with FORCE RLS and composite
  FKs (a run's text must belong to its own version; evidence must point at
  a page of the same tenant). Three-layer tests: `ExtractionRunPolicy` in
  `spec/policies/document_policies_spec.rb`, the request spec, and the
  raw-SQL entries in `spec/security/row_level_security_spec.rb`.
- Not built: review, per-tenant opt-in for sending content to the provider,
  cost computation, accuracy measurement against an annotated dataset.
