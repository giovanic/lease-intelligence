# ADR-0009: LLM Provider Abstraction

## Context

Structured contract field extraction depends on an LLM. Model choice,
pricing, and API shape change frequently across vendors, and evaluation
needs require swapping/comparing models without rewriting pipeline logic.

## Problem

Avoid coupling contract intelligence domain code to one LLM vendor's
SDK/API shape, and ensure every call's output is schema-validated rather
than trusted as free-form text.

## Decision

Define an internal LLM provider interface (e.g. "given normalized document
text + a prompt version + a target schema, return a schema-validated
structured result or a typed error") with one adapter per vendor. Record
provider, model, model version, and prompt version on every
`ExtractionRun` (see `docs/domain/contract-intelligence.md`).

## Alternatives considered

- **Call a vendor SDK directly from service/job code** — rejected: ties
  prompt engineering, schema validation, and vendor-specific response
  parsing together in one place, making model evaluation and vendor
  changes expensive and error-prone.
- **Trust raw LLM text output without schema validation** — rejected
  outright: contractual data (money, dates) demands structural guarantees
  before anything touches human review, let alone business logic.

## Consequences

- Positive: model/vendor swaps and side-by-side evaluation become
  adapter-level changes; schema validation is enforced once, centrally,
  not per call site.
- Negative: the interface and schema contract must be versioned
  deliberately (prompt version tracked per run) so that evaluation across
  prompt/model changes remains meaningful.

## Security implications

Document content sent to the LLM is untrusted input — the abstraction is
also where defenses against prompt injection embedded in contract text
must live (e.g. structural separation of "system instructions" from
"document content" in the prompt construction, never string-concatenating
untrusted text into an instruction channel). See
`.claude/rules/ai-processing.md`. Model confidence is never treated as a
calibrated probability for auto-approval (root `CLAUDE.md` §14).

## Implementation status

**Implemented** by ADR-0017: the `Llm` module (`app/services/llm.rb`) is
the interface — `extract(instructions:, document:, schema:)` returning
`Llm::Result` or a typed `Llm::*Error` — with two adapters:
`Llm::AnthropicProvider` (Claude through the `anthropic` gem, structured
outputs) and `Llm::OllamaProvider` (a local open-weight model, ADR-0018),
chosen per deployment by `LLM_PROVIDER`. Schema/evidence validation is `FieldExtraction::ValidateOutput`,
outside the adapter, so it holds for any vendor. Provider, model, model
version, prompt version and effort are recorded on every `ExtractionRun`.
