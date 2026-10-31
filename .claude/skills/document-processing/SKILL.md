---
name: document-processing
description: Use when building or changing any step of the document intelligence pipeline (upload, OCR, AI extraction, evidence validation, review handoff) on Lease Intelligence.
---

# Document Processing

## Required context

`docs/architecture/document-intelligence.md`, `docs/domain/documents.md`,
`docs/domain/contract-intelligence.md`, ADR-0007, ADR-0008, ADR-0009,
ADR-0011, ADR-0012, `.claude/rules/ai-processing.md`,
`.claude/agents/ai-document-engineer.md`.

## Workflow

1. Identify which pipeline stage you're touching: upload/validation,
   checksum/storage, text extraction, OCR, normalization, classification,
   structured AI extraction, schema validation, evidence validation,
   review handoff.
2. Confirm the stage is asynchronous if it involves OCR/LLM calls or any
   slow I/O — nothing in this pipeline should block a request/response
   cycle.
3. Confirm idempotency: re-running the stage (e.g. after a job crash)
   must not double-process or double-charge an external provider.
4. For OCR/LLM calls: go through the provider abstraction, never a
   vendor SDK directly (ADR-0008/ADR-0009).
5. For extraction output: confirm schema validation rejects any field
   with no `EvidenceReference`, and confirm the `ExtractionRun` records
   provider/model/model version/prompt version/status/cost/timing.
6. Confirm `ExtractedField` records are immutable — any correction
   produces a new `ReviewDecision`, not a mutation.
7. Confirm nothing downstream (obligations, dashboards) reads directly
   from `ExtractedField` instead of an approved `ReviewDecision`.
8. Handle provider failure explicitly: what does the user/reviewer see
   when OCR or the LLM call fails? It must be a visible, retryable
   failure state, not a silent drop.

## Validation

Test the stage with: a successful run, a provider timeout/error, and (for
extraction) a schema-invalid or evidence-missing response, confirming
each is handled per the rules above.

## Output

The pipeline stage implementation plus tests for the three scenarios
above, and a note on what accuracy/limitations were observed if this
touches extraction quality (never an unverified accuracy claim).
