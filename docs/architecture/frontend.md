# Frontend Architecture

Status: implemented — login, organization picker, and a routed
workspace (React Router in declarative mode, ADR-0014) with properties,
counterparties and leases screens (list / detail / create-edit), and a
"Documentos" section on the lease screen (`features/documents`: upload,
new version, version history, open a file in a new tab through a
5-minute link — ADR-0015). Pieces:
`services/` API client (`apiClient.ts`, the only `fetch` caller; sends
JSON, or `FormData` as multipart for uploads; sends
`X-Tenant-Id`, maps the error envelope — including 422 `details` — to
`ApiError`; `apiRequestPage` for `{ data, meta }` collections), hooks
`useSession` / `useTenantSelection` (selected tenant per tab in
`sessionStorage`, always re-confirmed by `GET /api/v1/current_membership`),
`useApiQuery` (loading/error/success per request key, no cache),
`useSubmission` (form submit + field errors), `useListParams` (filters
and page in the query string), `state/workspace.ts` (the confirmed
organization + a UX-only `canEdit`), and `src/types/api.ts` mirroring the
Rails serializers. No state library or test runner yet.

## Stack as actually declared in `apps/web/package.json`

React 19, TypeScript ~7.0 (project references split into
`tsconfig.app.json` / `tsconfig.node.json`), Vite 8, oxlint for linting,
`react-router` 8 (ADR-0014). No test runner, no data-fetching library, no
UI component library are installed yet. Any of these additions needs a stated architectural
justification before being added (root `CLAUDE.md` §4 / §9).

## Structure (in place since the Lease Management phase)

```
apps/web/src/
  pages/        route-level components
  features/     feature-scoped UI + logic (e.g. leases, documents, review)
  components/   shared, presentational, reusable components
  hooks/        shared React hooks
  services/     API client layer — the ONLY place that calls fetch/axios
  types/        shared TypeScript types, ideally generated/aligned with the
                Rails API's JSON response shapes
  state/        app-level state management, if/when needed
```

## Conventions

- All HTTP calls go through `services/` — no component calls `fetch`
  directly. This is what lets tenant/auth headers, error handling, and
  response typing stay in one place.
- Every data-driven view implements four states explicitly: loading, empty,
  error, success. Do not ship a view that only handles the happy path.
- Contract review screens must support side-by-side document viewer +
  extracted-field editor (per `apps/api/CLAUDE.md` §12) — this is a
  deliberate UX requirement, not incidental layout.
- The interface targets enterprise users: favor clarity, density, and
  predictability over decorative UI.
- TypeScript strictness: rely on the project's `tsconfig` strict settings;
  do not add `any` to work around a typing problem — fix the type.

## What does not exist yet (do not assume)

No design system, no form library decision, no test runner (no
Vitest/Jest configured — screens are verified by build/lint and a manual
or scripted browser run). The tenant is deliberately **not** in the URL
(ADR-0014); routes render only after the session and organization gate in
`App.tsx`. The production reverse proxy must serve `index.html` for
unknown non-`/api` paths (history fallback). The API is always reached at the
relative path `/api/v1` (same-origin, ADR-0013); `VITE_API_PROXY_TARGET`
only changes where the dev proxy forwards to (default
`http://127.0.0.1:3000`).
