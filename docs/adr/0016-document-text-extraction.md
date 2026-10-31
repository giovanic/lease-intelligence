# ADR-0016: Document Text Extraction (native PDF text + Tesseract OCR)

## Context

The pipeline in `docs/architecture/document-intelligence.md` starts with
"attempt native PDF text extraction, fall back to OCR". ADR-0008 decided
that OCR goes through an internal provider interface but chose no vendor
and no data model. What is true in the code at this point:

- `DocumentVersion` (ADR-0015) is an immutable, tenant-owned file:
  PDF, JPEG, PNG or TIFF, 1 B–50 MB, bytes reached only through
  `Documents::FileStore`.
- Sidekiq is the job backend (ADR-0006); `ApplicationJob#within_tenant`
  is the only way a job touches tenant data. No product job exists yet.
- `ActiveJob::Base.enqueue_after_transaction_commit` is `false`, and every
  tenant-scoped request runs inside one transaction (`TenantScoped`).
- The worker image (`apps/api/Dockerfile`) has `libvips` but no OCR or
  PDF-rendering binary.

## Problem

Turn every uploaded version into per-page text that the later AI
extraction (ADR-0009) and evidence references (ADR-0011: document version
+ page + span) can point to — reproducibly, inside the tenant boundary,
without sending contract content to a third party, and without letting
a hostile file take the worker down.

## Decision

### Engines

- **Native PDF text: the `pdf-reader` gem** (pure Ruby, no system
  dependency), page by page.
- **OCR: Tesseract** (`tesseract-ocr` + `tesseract-ocr-por`), run locally
  as a CLI through the OCR provider interface (`Ocr::TesseractProvider`).
  Contract content never leaves our infrastructure.
- **PDF page rasterization for OCR: `pdftoppm` (`poppler-utils`)**, inside
  the Tesseract adapter — Tesseract does not read PDF. This is an adapter
  detail: a vendor that accepts PDF directly would not need it.

The external binaries are called with `Open3` and an **argument array**
(never a shell string), on files in a private temp directory, with a
wall-clock timeout that kills the process. No document content is part of
any argument — only temp file paths we generate.

### Fallback rule (per page)

A PDF page whose native text has fewer than 20 non-whitespace characters
is treated as scanned and sent to OCR; the other pages keep their native
text. Images (JPEG/PNG/TIFF) always go to OCR. Each page records its
`source` (`native` or `ocr`), so a reviewer knows whether a value came
from OCR.

### OCR provider interface (ADR-0008)

`recognize(path:, content_type:, page_numbers:) -> [Ocr::Page(number, text)]`,
plus `engine` / `engine_version`. Failures are typed: `Ocr::TimeoutError`,
`Ocr::UnreadableFileError`, `Ocr::UnavailableError`. Layout/coordinates are
not part of the first interface (Tesseract's are poor and nothing consumes
them yet); they are the extension point when evidence needs bounding boxes.
Specs use a fake provider; the real adapter has its own spec against the
binaries.

### Data model (tenant-owned, FORCE RLS, composite FKs)

- `document_text_extractions` — one attempt over one `DocumentVersion`:
  `status` (`pending` → `running` → `succeeded` | `failed`),
  `page_count`, `native_page_count`, `ocr_page_count`, `engine` details
  (pdf-reader / tesseract versions), `error_code` (fixed vocabulary, never
  a raw exception message that could echo file content), `requested_by_id`
  (nullable: automatic run after upload), `started_at`, `finished_at`.
  A partial unique index allows **at most one pending/running extraction
  per version**.
- `document_text_pages` — `page_number`, `source`, `text`; append-only
  (trigger rejects UPDATE/DELETE, like `document_versions`). All pages of
  an attempt are written in one transaction when it succeeds, so an
  attempt never has a partial set of pages.

Reprocessing creates a **new** extraction; earlier attempts and their
pages are kept (a later `ExtractionRun` references the exact extraction it
read). The "current" text of a version is its latest succeeded extraction.

### Flow

1. `Documents::CreateDocument` / `AddVersion` call
   `DocumentText::RequestExtraction` explicitly (no model callback) in the
   upload transaction: it inserts the `pending` extraction and enqueues
   `ExtractDocumentTextJob(tenant_id, extraction_id)`.
2. The job class sets `enqueue_after_transaction_commit = true`, so it is
   pushed to Redis only after the upload commits (and never if it rolls
   back).
3. The job (queue `documents`) marks `running` in a short `within_tenant`,
   downloads the bytes and runs the engines **outside** any transaction,
   then writes pages + `succeeded` (or `failed` + `error_code`) in a second
   `within_tenant`. A finished extraction makes the job a no-op
   (idempotent re-delivery).
4. Expected failures (unreadable/encrypted PDF, timeout, too many pages,
   OCR unavailable) end in `failed` without a retry — reprocessing is a
   human action. Unexpected errors are retried by Active Job (3 attempts);
   when they run out, the extraction is marked `failed` (`internal_error`).
5. `POST /api/v1/document_versions/:id/text_extractions` (owner/admin/
   manager) requests a new attempt when none is pending/running. A
   pending/running attempt older than 1 hour is considered abandoned
   (worker crash) and is closed as `failed` (`abandoned`) so it can be
   retried.

### Limits

At most 300 pages per file (`too_many_pages`); a PDF page is rendered with
its longest side capped at 3508 px (A4 at 300 DPI — a cap, not a DPI, so a
huge MediaBox cannot become a gigapixel image); per page
60 s for `pdftoppm` and 120 s for `tesseract`. A dedicated `documents`
Sidekiq queue keeps slow OCR from starving `default`/`mailers`.

### API exposure

The version JSON gains `text_extraction` — the latest attempt's status,
page counts, error code and timestamps — but **not the text**. Reading
the text is part of the review screen (a later phase), with its own
authorization review.

## Alternatives considered

- **Cloud OCR (AWS Textract, Azure Document Intelligence)** — better
  accuracy and coordinates, but per-page cost and contract content sent to
  a third party (LGPD processor agreement, data residency). Deferred: the
  provider interface allows adding one as a second adapter, compared
  against an annotated dataset first.
- **`pdftotext` for native text** — better layout handling, but would have
  meant two poppler entry points for different jobs; `pdf-reader` keeps the
  native path in-process with no binary. `pdftoppm` is still needed for
  rasterization.
- **Ghostscript or ImageMagick for rasterization** — Ghostscript has a long
  history of code-execution CVEs on untrusted PDFs, and ImageMagick
  delegates PDF to Ghostscript. Rejected.
- **libvips (`ruby-vips`) for rasterization** — already in the image, but
  would add a gem and depends on how the distro built libvips (poppler
  support); `pdftoppm` is the direct, explicit tool.
- **Whole-document fallback (OCR everything if the document has little
  text)** — wasteful and loses good native text on mixed documents
  (signed pages scanned and appended to a digital contract). Rejected for
  per-page.
- **Overwrite one extraction row per version on reprocess** — loses the
  history an AI run must point to. Rejected.

## Consequences

- Positive: no third-party processor for contract content; no per-page
  cost; text traceable to version + page + source; vendor swap is one new
  adapter.
- Negative: Tesseract accuracy on poor scans is limited and unmeasured
  (no annotated dataset yet); `tesseract-ocr`, `tesseract-ocr-por` and
  `poppler-utils` become system dependencies of the worker image, CI and
  every developer machine; OCR is CPU-heavy on the worker.

## Security implications

- Untrusted files are parsed by `pdf-reader` (in-process), `pdftoppm` and
  `tesseract` (subprocesses). Mitigations: argument arrays, no shell,
  temp files with generated names, timeouts that kill the process group,
  a minimal environment for the child (`unsetenv_others`: none of the
  worker's secrets such as `RAILS_MASTER_KEY` or database/storage
  credentials), a 3 GiB address-space limit (`rlimit_as`), the page cap,
  the render-size cap, and errors reduced to a fixed `error_code`. A malicious PDF that
  hangs `pdf-reader` in-process is not bounded by a subprocess timeout —
  the page cap and Sidekiq's job-level visibility are the mitigations;
  sandboxing the parsers (separate container, seccomp) is a follow-up.
- Extracted text is contract content: never a job argument, never
  returned by the API in this phase, kept behind FORCE RLS. Pages are
  inserted one by one with bind parameters (not `insert_all`, which inlines
  values as SQL literals) and `filter_parameters` masks the exact name
  `text`, so SQL logs and `#inspect` show `[FILTERED]`. Caveat: Rails turns
  prepared statements off whenever `query_log_tags_enabled` is on — only in
  `config/environments/development.rb` today — and then binds are inlined
  and the development log *does* contain page text. Production has neither
  that setting nor SQL at its `info` log level.
- The reprocess endpoint authorizes through Pundit (editor roles) and
  finds the version under RLS; a version of another tenant is a 404.

## Implementation status

**Accepted — implemented** (`feat/document-text-extraction`):
`document_text_extractions` / `document_text_pages` (FORCE RLS, composite
FKs, page immutability trigger), `Ocr` interface + `Ocr::TesseractProvider`
+ `Ocr::Subprocess`, `DocumentText::*` services, `ExtractDocumentTextJob`
(queue `documents`), `POST /api/v1/document_versions/:id/text_extractions`,
`text_extraction` on the version JSON, status column + retry in the SPA's
"Documentos" section. Not built: reading the text through the API, layout
coordinates, a parser sandbox, an accuracy measurement of Tesseract on
real contracts.
