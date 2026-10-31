# ADR-0008: OCR Provider Abstraction

## Context

Scanned/image-based contract pages require OCR before text-based
extraction can run. OCR vendors vary in accuracy, pricing, and API shape,
and may need to change over the product's life.

## Problem

Avoid coupling the document pipeline to one OCR vendor's SDK/API shape
directly in domain code.

## Decision

Define an internal OCR provider interface (e.g. "given a file, return
normalized page text + optional layout/coordinate data") with one adapter
implementation per vendor. Domain/pipeline code depends only on the
interface, never on a vendor SDK type directly.

## Alternatives considered

- **Call the OCR vendor's SDK directly from pipeline/job code** —
  rejected: locks the product into one vendor's API shape, response
  format, and error semantics throughout the codebase, making a future
  vendor change or multi-vendor fallback strategy expensive.
- **No abstraction, vendor logic embedded per use site** — rejected for
  the same reason, compounded by duplicted error-handling logic.

## Consequences

- Positive: vendor swap or A/B comparison requires only a new adapter, not
  a pipeline rewrite; easier to unit-test pipeline logic against a fake
  adapter.
- Negative: the interface must be designed carefully up front to capture
  what different vendors can realistically provide (not over-fit to one
  vendor's especially rich response format); some vendor-specific
  capabilities may not fit the common interface and would need an
  explicit extension point.

## Security implications

Uploaded document content is untrusted input and is treated as such
regardless of which OCR vendor processes it — see
`.claude/rules/ai-processing.md`. The adapter boundary is also a natural
point to enforce consistent handling of provider credentials (via Rails
encrypted credentials / environment variables, never hardcoded).

## Implementation status

**Decided, not implemented.** No OCR integration, no provider interface,
and no vendor selection exist in the codebase yet.
