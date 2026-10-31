# Domain: Documents

Status: **implemented** (Document Management phase, `feat/document-upload`):
`ContractDocument`, `DocumentVersion`, upload, new versions and file
access, API + the "Documentos" section of the lease screen. Storage and
access design: `docs/adr/0015-document-file-storage-and-access.md`.
Not built yet: page count, OCR/extraction (`ExtractionRun`), deletion.

## Entities

- **ContractDocument** (`contract_documents`, tenant-owned, FORCE RLS) —
  the conceptual document slot of a lease: `kind` (`original_contract` —
  at most one per lease, partial unique index; `amendment`; `other`) and
  `title`. Belongs to a `Lease` through a composite FK on
  `(lease_id, tenant_id)`.
- **DocumentVersion** (`document_versions`, tenant-owned, FORCE RLS) — an
  immutable file of a document: `version_number` (1, 2, … per document),
  `storage_key` (`tenants/<tenant_id>/document_versions/<id>`),
  `original_filename` (sanitized base name), `content_type` (detected
  from the bytes: PDF/JPEG/PNG/TIFF), `byte_size` (1 B–50 MB), `sha256`,
  `uploaded_by_id`, `created_at` (= upload time; no `updated_at`).
  Composite FK on `(contract_document_id, tenant_id)`.

There are no Active Storage `blobs`/`attachments` tables: the version row
is the only reference to the stored bytes (ADR-0015).

## Relationships

```
Lease 1---* ContractDocument
ContractDocument 1---* DocumentVersion
DocumentVersion 1---* ExtractionRun      (planned)
```

## Rules (and where they are enforced)

- A `DocumentVersion` is never updated or deleted: a database trigger
  (`document_versions_immutable`) rejects both, and the model is
  `readonly?` once persisted. A correction is a new version
  (`Documents::AddVersion`, which locks the document row so concurrent
  uploads get distinct numbers).
- The same bytes are stored once per tenant: unique
  `(tenant_id, sha256)`; the API's 422 names the existing document and
  version.
- File type is decided by magic bytes, not by extension or declared
  Content-Type (`Documents::InspectUpload`).
- Files are private. The API never returns the storage key; the bytes are
  reached through `POST /api/v1/document_versions/:id/download_link`
  (5-minute link bound to user + tenant + version) and
  `GET /api/v1/document_files/:token`, which also requires the session, a
  live membership, RLS and Pundit. Active Storage's own routes are not
  drawn.
- Reading is open to any active member; uploading (new document or
  version) to owner/admin/manager (`ContractDocumentPolicy`,
  `DocumentVersionPolicy`).
- A `DocumentVersion` is the unit an `ExtractionRun` will operate on, so
  extraction results stay traceable to the exact bytes that produced them.

## API

See the header comments of `Api::V1::ContractDocumentsController`,
`DocumentVersionsController`, `DocumentDownloadLinksController` and
`DocumentFilesController`; the request specs in
`spec/requests/api/v1/contract_documents_spec.rb` and
`document_files_spec.rb` encode the contract. Uploads are
`multipart/form-data`, accepted only by those two upload actions
(`accepts_multipart_body`, `RequestOriginVerification`).
