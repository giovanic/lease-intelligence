---
applies_to: apps/api/app/controllers/**, apps/api/config/routes.rb
---

# API Rules

- Base path `/api/v1`. Version explicitly if a breaking change to a
  resource's shape is needed later — do not mutate an existing version's
  response shape in a breaking way.
- Use REST conventions (resourceful routes, standard verbs). Avoid
  bespoke RPC-style actions unless a resource genuinely doesn't fit CRUD
  semantics.
- Return predictable, consistent JSON structures across endpoints
  (consistent envelope/error shape) — pick one serialization convention
  and apply it everywhere, don't let each controller invent its own
  response shape.
- Use consistent, correct HTTP status codes (200/201/204 for success
  variants, 400/401/403/404/422 for client errors, 500 only for genuine
  server faults).
- Validate all input parameters server-side regardless of what the
  frontend already validated.
- Authorize every action server-side via Pundit. Never trust a
  `permissions`/`role` field sent back by the frontend.
- Paginate any collection endpoint that can grow unbounded (leases,
  documents, audit events) — do not return an unbounded array "for now."
- Document each endpoint's request/response shape as it's built (inline
  comments are not sufficient for an API contract — prefer a request spec
  that encodes the contract, plus any API documentation convention
  adopted later).
- CORS must be explicitly configured (currently missing — see root
  `CLAUDE.md` §3) before this API can be called from `apps/web` across
  origins in development.
