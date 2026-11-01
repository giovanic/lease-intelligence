# ADR-0019: Review Decisions and the Review Screen

## Context

ADR-0012 decided that no AI-extracted value becomes a contractual fact
without a human decision, and ADR-0011/0017 made every `ExtractedField`
carry verified evidence (page + character span of the stored text). What
exists: immutable `extraction_runs` / `extracted_fields` /
`evidence_references`, a read-only "Campos (IA)" panel, short-lived
same-origin file links that an `<iframe>` can open (ADR-0015), and no way
to read a page's full text through the API (ADR-0016 deferred that to the
review screen). `ContractualCondition` does not exist yet.

## Problem

Let a reviewer approve, correct or reject each candidate — quickly, next to
the document — keeping the AI output untouched, every decision
attributable, and the corrected value as strictly typed as the original.

## Decision

### `review_decisions` (tenant-owned, FORCE RLS, append-only)

One row per human action on one `ExtractedField`:

- `decision`: `approved` (the AI value as is), `corrected` (approved with
  the reviewer's value), `rejected` (with an optional `reason`).
- A corrected value uses the same typed columns as `extracted_fields`
  (`value_date`, `value_integer`, `value_amount numeric(15,2)` +
  `value_currency`, `value_text`, `value_tax_id`). `value_type` is copied
  from the field and enforced by a composite FK to
  `extracted_fields (id, value_type, tenant_id)`, so a correction can never
  have another type than the field; the same `COALESCE(CASE ...)` check
  guarantees the right column is set. Approved/rejected rows carry no
  value.
- `reviewed_by_id` (required), `reason` (≤ 1 000 chars), `created_at`.
  A trigger rejects UPDATE/DELETE: changing one's mind is a new decision,
  and the field's current state is its latest decision. History stays.
- The corrected value is validated by the same rules as AI output
  (`FieldExtraction::FieldValue`, extracted from `ValidateOutput`): type,
  vocabulary, ranges, decimal string for money.
- Only fields of the version's **latest succeeded run** can be decided —
  deciding on an outdated run would make two runs' answers compete
  (409 `stale_run`).

### Who

Owners, admins, managers and **analysts** decide
(`ReviewDecisionPolicy`); viewers read. Same tenant only; another
tenant's field is a 404.

### API

- `POST /api/v1/extracted_fields/:id/review_decisions`
  `{ review_decision: { decision, value?, reason? } }` → 201; `value` has
  the same shape the run JSON shows for that `value_type`.
- `GET /api/v1/extraction_runs/:id` adds, per field, `review` (its latest
  decision, with reviewer and corrected value) and `review_count`, and a
  run-level `review_summary` (approved / corrected / rejected / pending).
- `GET /api/v1/extraction_runs/:id/pages/:page_number` → the full text of
  one page of the text the run read (`source`, `text`), for highlighting
  the evidence. Readable by every active member — the same audience that
  can already download the whole file.

### Review screen

`/leases/:leaseId/extraction-runs/:runId/review`, two columns (stacked on
narrow screens):

- **Document**: the file in the browser's own viewer, in an `<iframe>`
  over a fresh 5-minute link (images in an `<img>`), and a "Texto da
  página" tab with the cited span highlighted. Clicking an evidence opens
  its page there. No PDF library: native viewer + our own text with exact
  offsets (decided with the product owner).
- **Fields**: each candidate with its evidence, current decision
  ("Pendente", "Aprovado", "Corrigido", "Rejeitado" + who/when) and actions
  Aprovar / Corrigir (typed inline form) / Rejeitar (optional reason).

### Boundary

Decisions are stored, not yet consumed: `ContractualCondition` (next
phase) is the only thing allowed to read approved/corrected values.
Nothing reads `extracted_fields` or `review_decisions` as contract terms
in this phase; the screen says so.

## Alternatives considered

- **Mutable status column on `extracted_fields`** — simplest, but mutates
  AI output and loses who decided what and when. Rejected (ADR-0011/0012).
- **Approve a whole run at once** — fast, but turns review into a single
  click over many values; per-field decisions are the control. A "approve
  all pending" shortcut can come later, still writing one decision per
  field.
- **pdf.js for the viewer** — page navigation and in-PDF highlight, but a
  new dependency and bundle weight, and exact highlight would still need
  OCR coordinates we do not store. Rejected for now.

## Consequences

- Positive: every value that will feed contract terms has a named human
  decision on record; corrections are typed and validated like AI output;
  the AI output stays intact for evaluation (decisions are labels for the
  future annotated dataset).
- Negative: the full page text is now readable through the API (members
  only); review is per field, which costs clicks on long contracts; the
  iframe link expires after 5 minutes (the screen fetches a new one on
  demand).

## Security implications

- New tenant-owned table with FORCE RLS, composite FKs to the field (and
  its type) and tenant; Pundit on every action; three-layer isolation
  tests.
- Page text: contract content, returned only to active members of the
  tenant, after RLS + Pundit (`ExtractionRunPolicy#show?`); never logged
  (JSON responses are not logged; `value_text`, `reason` and `text` are in
  `filter_parameters`).
- A reviewer's correction is untrusted input: validated server-side by the
  catalog rules; `reason` is plain text (React escapes it on render).

## Implementation status

**Accepted — implemented** (`feat/human-review`): `review_decisions`
(FORCE RLS, composite FK pinning type and tenant, immutability trigger),
`ReviewDecision`, `FieldExtraction::FieldValue` (shared with
`ValidateOutput`), `ContractReview::RecordDecision`, `ReviewDecisionPolicy`
/ `ExtractedFieldPolicy`, `POST /api/v1/extracted_fields/:id/review_decisions`,
`GET /api/v1/extraction_runs/:id/pages/:page_number`, review data on the
run JSON, and the SPA review screen. Verified end to end in the browser on
a run produced by the local model (approve, correct, reject, an invalid
correction refused, evidence highlighted). The PDF itself was checked by
its response (200, `application/pdf`, inline, `X-Frame-Options:
SAMEORIGIN`, not blocked) — the headless test browser has no PDF viewer to
render it. Not built: "approve all pending", `ContractualCondition`.
