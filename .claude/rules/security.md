---
applies_to: apps/api/**, apps/web/**
---

# Security Rules

- Never disable or weaken RLS, Pundit authorization, or any other access
  control to make a test, migration, or feature "work." Fix the actual
  cause of the conflict (root `CLAUDE.md` §4).
- Every controller action authorizes via Pundit before acting. Deny by
  default; an action with no explicit policy check is a bug, not an
  implicit allow.
- File access: private storage only (ADR-0007). Never return a permanent
  public URL for a contract document; always issue a short-lived, scoped
  signed URL after an authorization check.
- Never log contract contents, extracted personal data, credentials, or
  full document text. Review `config/initializers/filter_parameter_logging.rb`
  when adding any new sensitive parameter.
- Secrets live in Rails encrypted credentials or environment variables —
  never hardcoded, never committed.
- Treat uploaded document content as untrusted input end-to-end: never
  interpolate it unescaped into an executed command, and never give an
  LLM provider unrestricted, document-controllable instructions (see
  `.claude/rules/ai-processing.md`).
- Rate-limit authentication and upload endpoints via Rack::Attack once
  configured (the gem is present but not yet configured — configuring it
  is a prerequisite for shipping public-facing auth/upload endpoints).
- LGPD: minimize personal data retained in logs and third-party AI
  provider payloads; keep deletion/export feasibility in mind when
  designing new personal-data-bearing fields even if not required for
  MVP.
- Any security-sensitive change (auth, authorization, tenancy, file
  access, secrets) requires `security-engineer` review before being
  considered done (root `CLAUDE.md` §7, §15).
- Never fabricate or assume a security control is in place — verify
  against the actual code (e.g. check the DB role's RLS bypass
  attributes, check the actual Pundit policy file) before asserting
  something is secure.
