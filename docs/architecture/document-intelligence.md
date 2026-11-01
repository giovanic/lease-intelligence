# Document Intelligence Architecture

Status: partially implemented. Upload, checksum, private storage
(ADR-0015), text extraction — native PDF text, OCR fallback, per-page
storage (ADR-0016) — and LLM field extraction with verified evidence
(Claude through the `Llm` interface, ADR-0017) exist; human review and
fact approval do not. This describes the target design referenced by
`apps/api/CLAUDE.md` §8.

## Document lifecycle

`ContractDocument` (conceptual contract, e.g. "the lease for Unit 42") has
many `DocumentVersion`s (the original signed PDF, later an amendment file,
etc.). A `DocumentVersion` file is immutable once stored — corrections
produce a new version, never an overwrite.

## File storage

Active Storage backed by private, S3-compatible object storage (ADR-007).
No public/permanent URLs; access is via short-lived signed URLs issued only
after tenant/authorization checks. SHA-256 checksum computed on upload and
stored, both for integrity verification and duplicate detection.

## OCR pipeline

1. Upload, validate file type/size.
2. Checksum.
3. Store privately.
4. Attempt native PDF text extraction first.
5. Fall back to OCR when native extraction is insufficient (scanned
   documents, images).
6. Normalize pages (orientation, encoding) before downstream steps.

Steps 4–6 are implemented as described in ADR-0016: `pdf-reader` per page,
Tesseract (`por`) through `Ocr::TesseractProvider` for pages with fewer
than 20 non-blank characters and for images, text normalized once
(UTF-8, NFC, no NUL) before it is stored in `document_text_pages`.
Orientation correction is not done (Tesseract's default page segmentation
only).
OCR is accessed through a provider abstraction (ADR-008) so the vendor can
change without touching pipeline code. Uploaded document content is treated
as untrusted input throughout — it is never interpolated unescaped into any
executed command, and it is never sent to an AI provider with unrestricted,
user-controllable instructions (see `.claude/rules/ai-processing.md`).

## LLM abstraction

Structured extraction is performed through an internal LLM provider
interface (ADR-009): given normalized document text, request a
schema-validated structured output (parties, dates, monetary terms,
indexation clause, renewal terms, etc.). Each call records provider, model,
model version, prompt version, input document version, status, token
usage/cost where available, execution time, and errors — this is the
`ExtractionRun` record.

Implemented as described in ADR-0017: `Llm::AnthropicProvider`
(`claude-opus-5-5`, structured outputs, streamed, server-side refusal
fallback), the prompt `FieldExtraction::Prompt` (`lease-fields-v1`:
instructions in the system channel, the document alone in the user turn
with `&`/`<`/`>` escaped inside `<page>` elements), and
`ExtractContractFieldsJob`, requested by `ExtractDocumentTextJob` once a
text extraction succeeds. Cost is not stored (tokens + model are).

## Structured extraction and evidence references

Each field produced by an `ExtractionRun` becomes an immutable
`ExtractedField`, and each `ExtractedField` must carry one or more
`EvidenceReference`s pointing back to the source document/page/text span it
was derived from. A field with no evidence is not valid output — reject it
at the schema-validation step rather than let it reach review with no
justification shown to the human reviewer.

Implemented by `FieldExtraction::ValidateOutput` (ADR-0017): values are
checked against `FieldExtraction::Catalog` (types, vocabularies, ranges,
decimal strings for money), and each quote must be found — whitespace
collapsed — on the cited page of the exact text the run read; the stored
evidence is the character span in that page. Candidates that fail are
counted (`rejected_field_count`) and dropped.

## Human review

A `ReviewDecision` is a human's approve / edit-then-approve / reject action
on one `ExtractedField`. It never mutates the original `ExtractedField` —
the raw AI output stays immutable for audit and model-evaluation purposes.
An edit-then-approve produces a distinct "approved value" tied to the
decision, which is what feeds into contractual facts.

Implemented as described in ADR-0019: `review_decisions` (append-only,
`approved` / `corrected` / `rejected`), reviewers = owner, admin, manager,
analyst, and the review screen with the file in the browser's own viewer
next to the fields and the cited page text with the evidence highlighted.
`ContractualCondition` is not built, so no decision feeds anything yet.

## Contractual fact approval

Only an approved `ReviewDecision` can promote a value into the lease's
`ContractualCondition`s. Nothing downstream (dashboards, obligation
generation, calendar) may read directly from `ExtractedField` — they must
read from approved facts. This is the enforced boundary between "AI said"
and "the business has confirmed."
