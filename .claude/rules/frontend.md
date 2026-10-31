---
applies_to: apps/web/**
---

# Frontend Rules

- All HTTP calls go through a `services/` API client layer. No component
  calls `fetch`/`axios` directly. (This layer does not exist yet in
  `apps/web` — create it as part of the first feature that needs it,
  following `docs/architecture/frontend.md`'s target structure.)
- Every data-driven view implements loading, empty, error, and success
  states explicitly. A view that only handles the happy path is
  incomplete.
- The frontend's permission/role checks are a UX convenience only — never
  the authorization boundary. The backend independently authorizes every
  request (see ADR-0005). Do not build a feature's security around a
  frontend-only check.
- Contract review screens require a side-by-side document viewer +
  extracted-field editor layout (per `apps/api/CLAUDE.md` §12) — this is a
  deliberate product requirement, not a nice-to-have layout choice.
- TypeScript: fix the type, don't reach for `any` to silence an error.
  Keep `tsc -b` (the project's build-time typecheck) clean.
- Before adding a dependency (router, state management, UI library, data
  fetching library, test runner): state the architectural justification.
  None of these are installed yet — the first one added sets precedent,
  so make the choice deliberately rather than defaulting to whatever's
  most familiar.
- Keep pages/features/components/hooks/services/types separated per
  `docs/architecture/frontend.md`'s target structure once it's created —
  don't let page components accumulate business logic that belongs in a
  hook or service.
- Run `npm run build` (typecheck + build) and `npm run lint` (oxlint)
  before considering frontend work done.
