---
name: implement-api-endpoint
description: Use when adding or changing a REST endpoint under apps/api's /api/v1 namespace. Walks controller/service/serializer/policy/route conventions and required test coverage.
---

# Implement API Endpoint

## Required context

Root `CLAUDE.md` §11 (API conventions), `.claude/rules/api.md`,
`.claude/rules/backend.md`, `.claude/rules/multi-tenancy.md` (if the
resource is tenant-owned), `.claude/rules/security.md`. Inspect existing
controllers/routes for the established response-shape and error-handling
convention before inventing a new one.

## Workflow

1. Define the route under `/api/v1`, using resourceful REST conventions
   unless the resource genuinely doesn't fit CRUD.
2. Write/confirm the Pundit policy for the resource, covering both allow
   and deny — authorization happens in the controller via the policy, not
   ad hoc checks.
3. Keep the controller thin: strong-param validation, authorize, delegate
   to a service or direct model call for simple CRUD, render.
4. For multi-step business logic (not simple CRUD), push it into a
   service object with one public entry point.
5. Serialize responses consistently with whatever convention the codebase
   has established (or establish one deliberately if this is the first
   endpoint, and document it in `docs/architecture/backend.md`).
6. Paginate if the collection can grow unbounded.
7. If the resource is tenant-owned, confirm tenant context resolution
   happens server-side and the resource is scoped/RLS-protected — do not
   trust any tenant identifier from the request.
8. Handle not-found/forbidden/validation-error cases with correct, 
   consistent HTTP status codes.

## Validation

Write request specs covering: success path, validation failure,
unauthorized/forbidden access, and (if tenant-owned) cross-tenant access
denial. Run `bin/rspec`, `bin/rubocop`, `bin/brakeman`.

## Output

The endpoint, its policy, its service object (if applicable), and request
specs proving the behaviors above — with real command output confirming
they pass.
