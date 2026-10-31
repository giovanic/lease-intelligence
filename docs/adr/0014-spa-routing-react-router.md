# ADR-0014: SPA Routing with React Router (declarative mode)

## Context

Until the Lease Management phase the SPA (`apps/web`) had three screens
— login, organization picker, workspace shell — switched on session
state in `App.tsx`, with no router (`docs/architecture/frontend.md`).
That phase adds list/detail/form screens for properties, counterparties
and leases (nine routes), and every later module (documents, review
queue, obligations calendar) adds more. Users need:

- deep links — a lease, a property, the review of a document — that can
  be shared and reopened;
- working browser back/forward;
- filters and pagination in the URL, so a list survives a reload.

`.claude/rules/frontend.md` requires an explicit justification for the
first router, because it sets precedent for every later screen.

## Decision

Use **`react-router` (v8) in declarative mode**: `<BrowserRouter>`,
`<Routes>`/`<Route>`, `<Link>`/`<NavLink>`, `useParams`,
`useSearchParams`, `useNavigate`. Not its framework mode (file-based
routes, loaders/actions, SSR): data is fetched through `services/` and
hooks exactly as before, so the router only maps URLs to pages.

- Routes exist only after sign-in and organization selection; the
  session/tenant gate in `App.tsx` stays in front of the router, so an
  unauthenticated user never reaches a route.
- The selected tenant stays in `sessionStorage` + `X-Tenant-Id`
  (ADR-0013), **not** in the URL: a pasted link opens in the organization
  the reader is working in, and the API answers 404 if the record belongs
  to another one. Putting the tenant in the path would add a second,
  client-controlled source of tenant identity.
- List filters and pagination live in the query string
  (`useSearchParams`).
- The production reverse proxy (not built yet, ADR-0013) must serve
  `index.html` for unknown non-`/api` paths (history fallback); Vite's
  dev server already does.

The decision was taken when v7 was the version first proposed; v8 is the
current stable major at implementation time and keeps the same
declarative API, so v8 is what is installed.

## Alternatives considered

- **TanStack Router** — type-safe routes and schema-validated search
  params. Stronger typing, but a larger API surface and setup (a plugin
  or code generation for its best features) for a nine-route app.
  Revisit if untyped search params become a real source of bugs.
- **No library** (`history.pushState` + `popstate` by hand) — zero
  dependencies, but we would own params, links, nested layouts and
  scroll/back behavior ourselves; not a good use of effort.
- **React Router framework mode** — brings loaders/actions and a build
  plugin; overlaps with the `services/` + hooks layer and the same-origin
  deployment of ADR-0013 without a need for SSR.

## Consequences

- Positive: shareable URLs, browser navigation, URL-held list state; one
  well-known dependency (it pulls in two small packages,
  `@remix-run/route-pattern` and `cookie-es`, the latter only used by
  framework mode).
- Negative: route params and search params are untyped strings — pages
  must validate them (e.g. an unknown `status` falls back to "all").
- Data fetching stays hand-rolled (`hooks/useApiQuery.ts`); no caching
  library is introduced by this ADR. Revisit (e.g. TanStack Query) when
  cross-screen caching or invalidation becomes a real need.

## Security implications

None for authorization: the router is UX only, the API still authorizes
every request (ADR-0005). The deliberate choice to keep the tenant out of
the URL preserves ADR-0013's single tenant-selection path.

## Implementation status

**Implemented** in `apps/web` (Lease Management phase): `src/App.tsx`,
`src/pages/WorkspaceLayout.tsx`, `src/features/*`.
