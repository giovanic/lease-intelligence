---
name: architecture-decision
description: Use when a change requires a new architectural decision or revisits an existing one (crosses a domain boundary, changes a structural pattern like tenancy/versioning/provider abstraction, or adds a dependency with architectural weight) on Lease Intelligence. Produces an ADR, not an implementation.
---

# Architecture Decision

## Required context

`docs/adr/README.md` (index + template expectations),
`.claude/agents/software-architect.md`, root `CLAUDE.md` §4/§9/§15. Review
existing ADRs in the same area — this may be an update to an existing
ADR (e.g. resolving ADR-0006's open conflict) rather than a new one.

## Workflow

1. State the Context: what's true today that makes this decision
   necessary (cite the actual code/config, not assumption).
2. State the Problem precisely — not "what should we build" but the
   specific tension/question being resolved.
3. State the Decision clearly and concretely.
4. List Alternatives considered, each with why it was rejected (or why
   it remains viable but wasn't chosen now).
5. List Consequences — both positive and negative; don't omit the costs.
6. List Security implications explicitly, even if "none directly" — say
   so rather than leaving the section out.
7. Set Implementation status honestly: "Decided, not implemented,"
   "Decided, partially implemented," or "Implemented" — only the last if
   you've verified the actual code, and only after this ADR is reviewed/
   approved for anything with real architectural weight (root `CLAUDE.md`
   §15: wait for approval on significant architectural changes).
8. Add the new/updated ADR to the index in `docs/adr/README.md`.

## Output

A new or updated ADR file in `docs/adr/`, following the existing
numbering and template, plus the updated index. Implementation, if any,
is a separate follow-up step using `rails-engineer`/`ai-document-engineer`
as appropriate — this skill's output is the decision, not the code.
