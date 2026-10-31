# Product Vision

Status: planned product direction. None of the workflows described here are
implemented yet — see the root `CLAUDE.md` for the actual state of the code.

## Why this product exists

Companies that operate many leased properties — clinics, gyms, restaurant
chains, retail franchises, schools — manage their leases as scattered PDFs:
in email threads, shared drives, and the memory of whoever negotiated the
deal. Renewal deadlines are missed, readjustment clauses are applied late or
incorrectly, and nobody can answer "how much are we paying per m² across all
units in São Paulo" without a manual spreadsheet exercise.

Lease Intelligence centralizes the lease portfolio and uses AI to read the
documents the business already has, turning unstructured contracts into
structured, evidence-backed business data — while keeping a human in the
loop for anything that matters financially or legally.

## Target customers

B2B SaaS, initial market Brazil. Organizations with a multi-unit leased
property footprint:

- Healthcare networks (clinics, labs)
- Gyms and fitness chains
- Restaurant chains and franchises
- Retail chains
- Educational institutions (schools, courses)
- Any company with distributed leased operations (10+ properties is where
  manual tracking starts to break down)

## Core problems being solved

1. **No single source of truth for lease terms.** Rent values, indexation
   index, renewal windows, and termination clauses live in PDF files, not in
   queryable data.
2. **Deadlines are missed.** Renewal notice periods, readjustment dates, and
   obligation due dates are not tracked systematically.
3. **Amendments get lost.** The original contract and later amendments are
   rarely reconciled into "what are the actual current terms."
4. **No traceability.** Even when someone extracts a number into a
   spreadsheet, nobody can later point to which clause, which page, which
   document version it came from.
5. **AI extraction without verification is dangerous for contracts.** A
   wrong rent value or wrong renewal date has real financial/legal
   consequences, so raw LLM output must never be treated as fact.

## Product principles (binding — see `apps/api/CLAUDE.md` §2)

Evidence-first; human-in-the-loop for critical facts; immutable originals;
explicit versioning; historical preservation of conditions; strict tenant
isolation; auditability; async processing; provider-independent AI/OCR;
modular monolith before microservices; security/privacy by design; no
autonomous legal/financial decisions.

## What "done" looks like for the product vision (north star, not MVP)

A portfolio manager can open any property, see its current lease terms with
links back to the exact contract page each term came from, see upcoming
obligations and deadlines on a calendar, upload a new amendment and have it
proposed as a diff against current conditions pending their approval, and
trust that no other tenant in the system can ever see their data.
