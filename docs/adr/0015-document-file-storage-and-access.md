# ADR-0015: Document File Storage and Access

## Context

The Document Management phase stores the signed contract files of a
lease (`docs/domain/documents.md`). ADR-0007 decided "Active Storage
backed by private object storage, access only through short-lived signed
URLs issued after an authorization check", and ADR-0010 decided that
`DocumentVersion`s are immutable and append-only. Neither says how the
file reference is modeled nor how a browser actually receives the bytes.

What is true in the code at this point:

- `rails/all` is loaded, so the Active Storage engine is present and,
  by default, draws `/rails/active_storage/*` routes. Those routes serve
  a blob to anyone holding its signed id — a permanent token, with no
  Pundit check and no tenant context.
- No `active_storage_*` tables exist (`db/structure.sql`).
- Every tenant-owned table is protected by FORCE RLS keyed on
  `app_current_tenant_id()` (ADR-0003); Active Storage's
  `active_storage_blobs` / `active_storage_attachments` tables have no
  `tenant_id` and would sit outside that boundary.
- Tenant selection is the `X-Tenant-Id` header (ADR-0013). A browser
  navigation (opening a PDF in a tab, an `<iframe>` in the future review
  screen) cannot send that header.
- `config/storage.yml` has `test` and `local` Disk services only.

## Problem

1. Where does the reference to a stored file live, so that its metadata
   (key, original filename, checksum) is protected by RLS like every
   other tenant-owned row?
2. How does an authorized user open a file in the browser, given the
   tenant header cannot travel with a navigation, without issuing a
   permanent or bearer-only link?
3. What do we accept, and how do we detect the same file uploaded twice?

## Decision

**1. Active Storage's service layer only — no blobs/attachments.**
Files are written and read through `ActiveStorage::Blob.service` (the
configured `ActiveStorage::Service`: Disk in development/test, an
S3-compatible service once infrastructure exists), but the
`active_storage_blobs` / `active_storage_attachments` tables are not
installed and `has_one_attached` is not used. The `document_versions`
row (tenant-owned, FORCE RLS) holds everything about the file:
`storage_key`, `original_filename`, `content_type`, `byte_size`,
`sha256`, `uploaded_by_id`, `created_at`.

- Storage key: `tenants/<tenant_id>/document_versions/<version_id>`
  (per-tenant prefix: deletion/export of one tenant is a prefix
  operation — LGPD).
- `config.active_storage.draw_routes = false`: no Active Storage
  controller is reachable.
- `document_versions` rejects `UPDATE` and `DELETE` with a database
  trigger, so ADR-0010's immutability does not depend on application
  code. A correction is a new version.

**2. Downloads through an app-issued link valid for 5 minutes.**

- `POST /api/v1/document_versions/:id/download_link` (TenantScoped,
  Pundit `show?`) returns `{ url, expires_at }`. The URL is
  `/api/v1/document_files/<token>`, where the token is a
  `Rails.application.message_verifier` message with purpose
  `document_download`, `expires_in: 5.minutes`, carrying
  `{ version_id, tenant_id, user_id }`.
- `GET /api/v1/document_files/:token` requires the session cookie too.
  It verifies the token, requires `user_id == current_user.id`,
  re-resolves an *active* membership in the token's tenant
  (`Identity::SelectableMemberships`), runs inside `TenantContext`,
  loads the version under RLS, authorizes it again and streams the
  bytes (`Content-Disposition: inline`, the server-verified
  `Content-Type`, `X-Content-Type-Options: nosniff`,
  `Cache-Control: private, no-store`).
- A leaked URL is therefore useless to anyone else, useless after 5
  minutes, and useless to its own user once their membership is
  revoked. The bytes always pass through the app; the storage service
  never hands out its own URL.

**3. Accepted files and duplicates.**

- PDF, JPEG, PNG, TIFF, at most 50 MB, at least 1 byte. The type is
  decided by the file's leading bytes (magic numbers), never by the
  extension or the client's declared `Content-Type`.
- SHA-256 is computed by the app at upload. The same bytes cannot be
  stored twice in a tenant: unique index `(tenant_id, sha256)`; the API
  answers 422 naming the existing document/version.

## Alternatives considered

- **`has_one_attached` with the standard tables** — the idiomatic Rails
  path, but it puts every tenant's filenames and checksums in global
  tables without RLS, and it needs the default routes disabled anyway.
  Adding `tenant_id` + RLS to Active Storage's own tables means fighting
  the framework (blobs are created/analyzed/purged by its internals and
  jobs, outside our tenant context). Rejected.
- **S3 pre-signed URLs (redirect)** — offloads bandwidth, but requires
  `aws-sdk-s3` and a bucket now (no infrastructure exists, see root
  `CLAUDE.md` §3.4), needs a second path for Disk in development, and a
  pre-signed URL is a pure bearer token. Viable later for large files:
  the download controller is the single place to change.
- **Authenticated `GET` with the tenant header, fetched by the SPA as a
  Blob** — no token needed, but the whole file goes through JS memory
  and an `<iframe>`/new tab cannot use it directly. Rejected for the
  viewer use case.
- **Block duplicates only within one document, or just warn** — weaker;
  the domain asks to detect accidental re-uploads, and the same signed
  contract attached to two leases is almost always a mistake. Revisit if
  a legitimate case appears (e.g. one contract covering two properties).

## Consequences

- Positive: all file metadata is behind RLS and covered by the
  three-layer isolation tests; immutability is enforced by the database;
  one download path for every environment; no new dependency.
- Negative: we do not get Active Storage's analyzers, variants or
  direct uploads — page count, previews and direct-to-bucket upload must
  be built explicitly when needed (page count belongs to the OCR phase).
  An upload whose database commit fails after the bytes were written
  leaves an orphan object under the tenant prefix (logged; a cleanup
  sweep can be added later). Files stream through the Rails process.
- Production still uses the `local` Disk service; moving to private
  S3-compatible storage (ADR-0007) remains a deployment task.

## Security implications

This is the access-control path for contract files. The download token
is never sufficient on its own (session + same user + live membership +
RLS + Pundit), short-lived, and scoped to one version. Disabling Active
Storage routes removes a pre-authorized-by-default file endpoint. File
type is verified from content, and the response is served with the
verified type and `nosniff`. Original filenames can contain personal
data: they are stored only in the RLS-protected table, `:file` is added
to the filtered request parameters, and the download sets
`Content-Disposition` itself so Rails does not log "Sent data
<filename>".

Abuse limits: Puma rejects any request body over 51 MB with 413
(`http_content_length_limit`, also for chunked bodies) before Rails
parses — and buffers — a multipart body, which it would otherwise do
even for an unauthenticated request; Rack::Attack throttles uploads to
30/min per IP. The download token travels in the URL path, so it appears
in request logs; it is accepted only with the same user's session and
for 5 minutes.

## Implementation status

**Decided, implemented in the Document Management phase**
(`feat/document-upload`): see `docs/domain/documents.md`.
