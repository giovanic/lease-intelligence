# ADR-0013: SPA Authentication via Session Cookie and Tenant Selection via Header

## Context

ADR-0005 separates the Rails API (`apps/api`, `api_only`) from the React
SPA (`apps/web`) but left two security-relevant questions open:

1. How the SPA authenticates to the API (no token storage strategy was
   decided — `docs/architecture/frontend.md`).
2. How a request says which tenant it is operating as, given that a user
   can hold memberships in several tenants (`docs/domain/identity.md`) and
   that a client-supplied `tenant_id` must never be trusted on its own
   (`.claude/rules/multi-tenancy.md`).

Devise is already installed on `User`; Pundit and Rack::Attack are
declared in the `Gemfile`.

## Decision

### Authentication: Devise/Warden session in an httpOnly cookie

- Re-enable `ActionDispatch::Cookies` and `ActionDispatch::Session::CookieStore`
  in the API middleware stack (stripped by `api_only`). Cookie flags:
  `HttpOnly`, `SameSite=Lax`, `Secure` outside development/test.
- `POST /api/v1/session` signs in (Devise `sign_in`, which renews the
  session id — no session fixation), `DELETE /api/v1/session` signs out.
  Credential checking lives in a service object, not the controller.
- Devise `:timeoutable` expires an idle session server-side (the
  `last_request_at` timestamp lives in the signed/encrypted session).
- Devise `paranoid` mode + a single uniform 401 for any failed sign-in,
  so the endpoint does not reveal whether an email is registered.
- Rack::Attack throttles sign-in attempts by IP and by email.

**CSRF.** Cookie auth is ambient, so state-changing requests are
protected by three independent layers instead of Rails' form-token CSRF
(which assumes server-rendered forms):

1. `SameSite=Lax` — the browser does not attach the cookie to cross-site
   POST/PUT/PATCH/DELETE.
2. `RequestOriginVerification` — any non-GET/HEAD request carrying an
   `Origin` that is not in the configured allowlist, or a
   `Sec-Fetch-Site: cross-site` header, is rejected with 403.
3. Write endpoints only accept `application/json`, which a cross-site
   HTML form cannot send without a CORS preflight the API never grants.

**Same-origin deployment, no CORS.** The SPA is served from the same
origin as the API: in development the Vite dev server proxies `/api` to
Rails; in production a reverse proxy routes `/api` to Rails and
everything else to the static SPA. This makes the cookie first-party and
removes the need for `rack-cors` entirely (resolving root `CLAUDE.md` §3
item 2 by design rather than by adding a dependency). The Vite proxy is
configured in the frontend phase.

### Tenant selection: `X-Tenant-Id` header, validated against membership

- Tenant-scoped endpoints read the desired tenant from `X-Tenant-Id`.
  The value is treated as a *request*, never as authority: the
  `TenantScoped` controller concern looks up the current user's
  **active** membership for that tenant (via the memberships
  self-visibility RLS policy, user-only context) and requires the tenant
  itself to be `active`.
- Missing header → 400. Malformed id, no membership, suspended
  membership or non-active tenant → one uniform 403 (no distinction, so
  the endpoint is not an oracle for which tenant ids exist).
- On success the whole action runs inside `TenantContext.activate(tenant:,
  user:)` — one transaction with `SET LOCAL`, cleared in `ensure` — so
  RLS is enforced for every query of the request and nothing survives on
  the pooled connection.
- Pundit receives an `AuthorizationContext(user, membership)`; role
  decisions come from the membership, never from client input.

## Alternatives considered

- **JWT (`devise-jwt`).** New dependency; token readable by JS (XSS
  exfiltration), revocation needs a denylist table anyway. Rejected.
- **Opaque bearer token in a DB table.** Revocable and no new gem, but the
  token is still JS-readable. Rejected for the same XSS reason.
- **Tenant in the URL path (`/api/v1/tenants/:id/...`).** Explicit, but
  verbose routes for every resource with no security gain over a
  validated header. Rejected.
- **Current tenant stored in the session.** Breaks working in two tenants
  in two browser tabs; hidden server-side state. Rejected.

## Consequences

- Positive: no new gems; the credential is never exposed to JavaScript;
  logout and idle timeout are server-enforced; tenant resolution has one
  code path, tested in isolation and at request level.
- Negative: SPA and API must share an origin (a deployment constraint).
  Each tenant-scoped request is wrapped in one database transaction for
  its whole duration — acceptable for short CRUD requests; long-running
  work must move to background jobs (which establish their own context).
- Known limitation: with `CookieStore` the session lives in the cookie, so
  a *stolen* cookie stays valid after logout until idle timeout or a
  password change (Devise's salt check). `HttpOnly`, `Secure` and a short
  `timeout_in` reduce this; moving to a server-side session store is the
  upgrade path if the threat model requires immediate revocation.

## Security implications

Reviewed against `.claude/rules/security.md` and
`.claude/rules/multi-tenancy.md`: tenant is derived from server-side
membership; RLS remains the enforced boundary; context is
per-transaction; Pundit denies by default and every action must
authorize or explicitly skip (`verify_authorized`). Requires
`security-engineer` review before production use.

## Implementation status

Implemented on branch `phase/auth-tenant-context` (API only). The Vite
proxy and SPA login screen are not built yet.
