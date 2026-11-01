# Architecture Decision Records

This directory records *why* Lease Intelligence is built the way it is.
Each ADR documents a decision made (or explicitly deferred), the
alternatives considered, and the consequences — including security
consequences. An ADR describes intent; it does not by itself mean the
decision has been implemented. Check each ADR's **Implementation status**
field, and verify against the actual code before relying on it.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-modular-monolith.md) | Modular monolith | Decided, not implemented |
| [0002](0002-shared-schema-multi-tenancy.md) | Shared-schema multi-tenancy | Decided, not implemented |
| [0003](0003-postgresql-rls.md) | PostgreSQL Row-Level Security | Decided, not implemented |
| [0004](0004-uuid-primary-keys.md) | UUID primary keys | Decided, not implemented |
| [0005](0005-rails-api-react-frontend-separation.md) | Rails API + React frontend separation | Decided, partially scaffolded |
| [0006](0006-background-processing-sidekiq.md) | Background processing (Sidekiq) | Accepted — implemented |
| [0007](0007-private-object-storage.md) | Private object storage | Decided, partially implemented |
| [0008](0008-ocr-provider-abstraction.md) | OCR provider abstraction | Implemented (Tesseract adapter, ADR-0016) |
| [0009](0009-llm-provider-abstraction.md) | LLM provider abstraction | Implemented (Anthropic adapter, ADR-0017) |
| [0010](0010-document-contract-versioning.md) | Document and contract versioning | Decided, partially implemented (documents) |
| [0011](0011-evidence-first-architecture.md) | Evidence-first data architecture | Implemented (ADR-0017; review not built) |
| [0012](0012-human-in-the-loop-review.md) | Human-in-the-loop review | Decided, not implemented |
| [0013](0013-spa-session-auth-and-tenant-selection.md) | SPA session-cookie auth + `X-Tenant-Id` tenant selection | Implemented (API) |
| [0014](0014-spa-routing-react-router.md) | SPA routing with React Router (declarative mode) | Implemented |
| [0015](0015-document-file-storage-and-access.md) | Document file storage and access | Implemented |
| [0016](0016-document-text-extraction.md) | Document text extraction (native PDF text + Tesseract OCR) | Implemented |
| [0017](0017-contract-field-extraction-claude.md) | Contract field extraction with the Claude API | Implemented |

## How to propose a new ADR

Use the `architecture-decision` skill (`.claude/skills/architecture-decision/SKILL.md`).
Any change that alters a domain boundary, introduces a new external
dependency with architectural weight, or changes a security-relevant
mechanism (tenancy, auth, storage, AI provider contracts) should get an
ADR before implementation, per `.claude/agents/software-architect.md`.
