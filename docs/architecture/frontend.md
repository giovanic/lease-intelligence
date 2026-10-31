# Frontend Architecture

Status: first slice implemented — login, organization picker and an
empty workspace shell (`src/pages`), the `services/` API client
(`apiClient.ts`, the only `fetch` caller; sends `X-Tenant-Id`, maps the
API error envelope to `ApiError`), hooks `useSession` /
`useTenantSelection` (selected tenant per tab in `sessionStorage`,
always re-confirmed by `GET /api/v1/current_membership`), and
`src/types/api.ts` mirroring the Rails serializers. No router, state
library or test runner yet — screens switch on session state.

## Stack as actually declared in `apps/web/package.json`

React 19, TypeScript ~7.0 (project references split into
`tsconfig.app.json` / `tsconfig.node.json`), Vite 8, oxlint for linting. No
test runner, no router, no data-fetching library, no UI component library
are installed yet. Any of these additions needs a stated architectural
justification before being added (root `CLAUDE.md` §4 / §9).

## Target structure (to create when the first real feature lands)

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

No routing library decision, no design system, no form library decision, no
test runner (no Vitest/Jest configured). The API is always reached at the
relative path `/api/v1` (same-origin, ADR-0013); `VITE_API_PROXY_TARGET`
only changes where the dev proxy forwards to (default
`http://127.0.0.1:3000`).
