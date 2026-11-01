# ADR-0011: Evidence-First Data Architecture

## Context

AI-extracted contract fields are only useful if a human can verify them
quickly against the source document; otherwise review becomes "trust the
AI" by default, which the product explicitly rejects.

## Problem

Ensure every piece of AI-derived business data can be traced back to the
exact document/page/text it came from, structurally — not as an
afterthought or a best-effort log entry.

## Decision

Every `ExtractedField` must have one or more `EvidenceReference` records
pointing to its source (`DocumentVersion`, page, text span/snippet) as a
first-class, required relationship. Schema validation at the end of the
extraction step rejects fields with no evidence rather than letting them
reach the review queue unexplained.

## Alternatives considered

- **Evidence as optional metadata/free-text notes** — rejected: optional
  means it will sometimes be missing, which defeats the purpose; this must
  be structurally required, not a convention people are trusted to follow.
- **Evidence derived/reconstructed after the fact (re-run a search for the
  value in the document when a reviewer asks)** — rejected: unreliable
  (the same value might appear in multiple places, or not literally in the
  text if the model paraphrased), and defers a hard requirement to query
  time instead of extraction time.

## Consequences

- Positive: reviewers can always see exactly where a value came from,
  which directly supports trust in the review workflow and shortens review
  time; audit/compliance questions ("why did we believe the rent was X")
  have a concrete answer.
- Negative: requires the LLM provider abstraction (ADR-0009) to reliably
  return evidence alongside values — if a given prompt/model struggles to
  produce accurate evidence spans, that's a quality problem to solve in
  prompt design/evaluation, not a reason to make evidence optional.

## Security implications

Indirect: evidence-first architecture is what makes human review
meaningful rather than theater, which is the actual control preventing bad
AI output from becoming a business decision (ADR-0012).

## Implementation status

**Implemented** by ADR-0017: `ExtractedField` and `EvidenceReference`
(append-only, FORCE RLS) exist, and `FieldExtraction::ValidateOutput`
drops every candidate without a quote found on the cited page of the exact
text the run read; evidence is stored as character offsets into that page.
Not built: the review screen that shows evidence side by side with the
document (ADR-0012).
