# ADR-0007: Private Object Storage

## Context

Contract documents are sensitive (financial terms, counterparty personal
data under LGPD) and must be stored durably but never publicly accessible.

## Problem

Choose a file storage approach that supports large PDF/image files,
private access control, and works well with Rails.

## Decision

Use Active Storage (already available via Rails, `config/storage.yml`
present) backed by private, S3-compatible object storage. No service
should be configured for public read access; all access is mediated by
the application issuing short-lived signed URLs after an authorization
check.

## Alternatives considered

- **Public bucket with obscure/unguessable URLs** — rejected: "security
  through obscurity" is not acceptable for financial/legal contract
  documents; a leaked or logged URL would be a permanent exposure.
- **Store files directly in PostgreSQL (bytea)** — rejected: poor fit for
  potentially large PDF files, bloats database size/backups, no benefit
  over object storage for this use case.
- **Local disk storage** — rejected for anything beyond a throwaway dev
  environment: not durable, not scalable, incompatible with multi-instance
  deployment.

## Consequences

- Positive: durable, scalable, standard Rails integration via Active
  Storage, clear separation between "storage" and "access control" (access
  control lives in the app, not the storage layer's ACLs).
- Negative: every document access path must go through the app's
  authorization + signed-URL issuance; a shortcut that returns a raw
  storage URL anywhere is a direct vulnerability.

## Security implications

This is a core control for document confidentiality. Signed URLs must have
short expiry and must be scoped (not reusable indefinitely, not guessable
ahead of issuance). Checksums (SHA-256) recorded at upload time support
integrity verification independent of the storage layer.

## Implementation status

**Decided, not implemented.** `apps/api/config/storage.yml` exists only
as the Rails default template; no S3-compatible service is configured, no
signed-URL issuance flow exists, and no `ContractDocument`/
`DocumentVersion` model exists to attach files to.
