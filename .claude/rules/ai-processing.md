---
applies_to: apps/api/app/**
---

# AI Processing Rules

See `docs/architecture/document-intelligence.md`, ADR-0008, ADR-0009,
ADR-0011, ADR-0012 for full rationale.

- Access OCR and LLM providers only through the internal provider
  interface/adapter pattern — never call a vendor SDK directly from
  pipeline/domain/job code.
- Treat all document content as untrusted input. Structurally separate
  system/instruction content from document content when constructing a
  prompt — never string-concatenate untrusted document text into a
  channel the model treats as an instruction.
- Every `ExtractionRun` records provider, model, model version, prompt
  version, input document version, status, token usage/cost where
  available, execution time, and errors.
- Every `ExtractedField` must be schema-validated and must carry at least
  one `EvidenceReference` pointing to its source document/page/span.
  Reject fields with no evidence at the schema-validation step.
- `ExtractedField` records are immutable once created. A correction is a
  new `ReviewDecision`, never a mutation of the original extraction.
- Never treat model-reported confidence as a calibrated probability. Do
  not build any auto-approval path keyed on it.
- Only an approved `ReviewDecision` may feed into a `ContractualCondition`
  or anything downstream (obligations, dashboards). Nothing reads raw
  `ExtractedField`s as if they were fact.
- Handle provider failures explicitly: timeouts, rate limits, malformed/
  non-schema-conforming responses. Leave the record in a reviewable
  failure state; do not retry silently forever or swallow the error.
- Before claiming an extraction accuracy improvement (new prompt, new
  model), measure it against an annotated dataset — do not assert
  improvement from spot-checking a few examples.
