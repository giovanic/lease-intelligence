# ADR-0005: Rails API + React Frontend Separation

## Context

The product needs an enterprise-grade, interactive UI (side-by-side
document/extracted-data review, calendars, dashboards) and a
provider-agnostic backend suited for background processing and AI
pipelines.

## Problem

Choose between a traditional server-rendered Rails app (with or without
Hotwire) and a decoupled API + SPA architecture.

## Decision

Rails as an API-only backend (`config.api_only = true`, already set in
`apps/api/config/application.rb`) under `/api/v1`, with a separate React +
TypeScript SPA (`apps/web`) as the sole consumer of that API.

## Alternatives considered

- **Server-rendered Rails with Hotwire/Turbo** — rejected for this
  product's UI needs: the contract review experience (side-by-side
  document viewer with an interactive, evidence-linked field editor) and
  dashboard/calendar interactions are better served by a client-rendered
  SPA with rich local state than by Turbo-driven partial page updates.
- **Separate backend framework (e.g. Node) instead of Rails** — rejected:
  no stated benefit over Rails for this team/stack, and would fragment
  the backend ecosystem (ActiveRecord, Devise, Pundit, Sidekiq/background
  job ecosystem) that the product's engineering rules already assume.

## Consequences

- Positive: clean separation of concerns, independent deploy/scaling of
  frontend and backend, a conventional REST contract that's easy to
  document and test in isolation.
- Negative: requires explicit CORS configuration (currently missing — see
  root `CLAUDE.md` §3), requires an explicit API client layer on the
  frontend, requires care to never leak backend authorization assumptions
  into frontend-only checks (the frontend's permission UI is a UX
  convenience, never the actual authorization boundary).

## Security implications

Because the frontend is a separate, untrusted-by-the-backend client, the
backend must independently authenticate and authorize every request — the
backend must never trust a "permissions" field the frontend sends back to
it, and must never assume the frontend's UI-level restrictions are
sufficient (root `CLAUDE.md` §11: "Do not trust frontend permissions").

## Implementation status

**Decided, partially scaffolded.** `apps/api` is already `api_only`.
`apps/web` is an unmodified Vite/React/TS template with no API client
layer yet and no CORS configuration on the backend side — both must be
built before any real frontend-backend integration.
