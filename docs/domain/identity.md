# Domain: Identity & Tenancy

Status: **implemented** (schema, models, RLS, tests). `User`, `Tenant`,
`Membership`, `Invitation` exist in `apps/api/db/migrate/202610311332*`
and `apps/api/app/models/`. Devise is installed and the `User` model uses
it. Authentication, tenant selection and Pundit are implemented at the
API level per ADR-0013 (`/api/v1/session`, `/api/v1/me`,
`/api/v1/current_membership`).

## Entities (as implemented)

- **User** (`users`, no RLS — global, no `tenant_id`) — Devise
  (`:database_authenticatable, :registerable, :recoverable,
  :rememberable, :validatable, :trackable`). `email` (unique),
  `encrypted_password`, `full_name` (required), plus Devise's
  recoverable/trackable columns. `has_many :memberships`,
  `has_many :tenants, through: :memberships`.
- **Tenant** (`tenants`, no RLS — root tenancy anchor, nothing to scope
  by) — `name`, `slug` (unique, lowercased, URL-safe format), `status`
  enum (`active`/`suspended`/`canceled`, DB check constraint).
  `has_many :memberships`, `has_many :invitations`.
- **Membership** (`memberships`, tenant-owned, RLS) — join of `User` and
  `Tenant`. `role` enum (`owner`/`admin`/`manager`/`analyst`/`viewer`,
  DB check constraint), `status` enum (`active`/`suspended`), optional
  `invitation_id` (traceability of how the membership was created).
  Unique on `(tenant_id, user_id)`.
- **Invitation** (`invitations`, tenant-owned, RLS) — targets an `email`,
  not necessarily an existing `User`. `role`, `status`
  (`pending`/`accepted`/`revoked`/`expired`), `token`
  (`has_secure_token`, unique), `expires_at`. At most one `pending`
  invitation per `(tenant_id, email)` (partial unique index).

## Relationships

```
User 1---* Membership *---1 Tenant
Tenant 1---* Invitation
Invitation 0/1---0/1 Membership   (optional, traceability of acceptance)
```

A user with no memberships has no tenant-scoped access at all. A user's
"current tenant" for a given request is resolved from an explicit tenant
selection validated against their memberships server-side — never trusted
blind from the client (`.claude/rules/multi-tenancy.md`). The "which
organizations am I in" bootstrap (listing memberships across tenants,
before any one tenant is active) is handled by a dedicated RLS policy —
see `docs/adr/0003-postgresql-rls.md` addendum and
`apps/api/app/services/tenant_context.rb`.

## Authorization model

Pundit installed. Policies receive an `AuthorizationContext(user,
membership)` (membership is nil outside tenant-scoped endpoints) and
decide allow/deny per action; `ApplicationPolicy` denies everything by
default. Only `UserPolicy#show?` and `MembershipPolicy#show?` exist so far. Role granularity
within a tenant is enforced in policies, not scattered as ad hoc
`if current_user.admin?` checks in controllers.

## Open questions

- Exact per-role permissions per domain (the five roles exist as an enum;
  what each can/cannot do per resource is not yet defined — that's
  Pundit policy work, not schema work).
- Whether property-level (not just tenant-level) authorization is needed
  for the "Operations / Store Manager" persona — likely post-MVP, kept
  extensible.
- **Invitation accept-by-token under RLS.** The invitee has no tenant
  context when following an invite link, so `Invitation.find_by(token:
  ...)` as currently modeled will be denied by RLS (correctly — no
  context, no access) once a real lookup is attempted. Recommended
  approach (not yet implemented): a third per-transaction session
  setting acting as a one-shot capability token
  (`SET LOCAL app.invitation_lookup_token`) plus an additional,
  narrowly-scoped SELECT policy checking `token = current_setting(...)`.
  Must be designed and reviewed by `security-engineer` before the
  accept-invitation endpoint is built — do not add a blanket
  "SELECT by token" policy, which would let any connection read every
  tenant's pending invitations.
