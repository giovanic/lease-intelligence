# Security Architecture

Status: planned. No authentication, authorization, or RLS exists yet in
the codebase. This document is the target posture; see
`.claude/agents/security-engineer.md` and `.claude/rules/security.md` for
operational rules.

## Layers of defense

1. **Database (RLS)** — the last line of defense; must hold even if
   application code has a bug. See `docs/architecture/multi-tenancy.md`.
2. **Authorization (Pundit)** — every controller action checks a policy
   against the current user + membership before acting. Deny by default.
3. **Authentication (Devise)** — standard session/token-based auth for the
   SPA-to-API relationship; credentials and secrets never logged.
4. **Input validation** — all input (including uploaded document content)
   is treated as untrusted.
5. **Rate limiting (Rack::Attack)** — gem present, not yet configured;
   needed especially on auth endpoints and upload endpoints.
6. **Secure file access** — private object storage, short-lived signed
   URLs only, no permanent public document links.
7. **Audit trail** — sensitive actions recorded as immutable `AuditEvent`s.
8. **Transport security** — HTTPS/TLS in all non-local environments.

## LGPD considerations

Contract data frequently contains personal data (counterparty signatories,
tenant employees). Minimize what's logged, ensure deletion/export
capabilities are at least considered in domain design even if not in MVP
scope, and never expose contract contents or extracted personal data in
application logs (`apps/api/CLAUDE.md` §9).

## Secrets management

Use Rails encrypted credentials (`config/master.key` /
`config/credentials.yml.enc`, already present) or environment variables for
anything environment-specific (API keys for OCR/LLM providers, storage
credentials, database URL). Never commit secrets to the repository.

## Threat model highlights (to formalize further as features are built)

- A malicious or compromised tenant user attempting to access another
  tenant's data (mitigated by RLS + Pundit + tests).
- A malicious document (crafted PDF, prompt-injection text inside a
  contract) attempting to manipulate the LLM extraction step or escape its
  sandboxed interpretation — see `.claude/rules/ai-processing.md`.
- Leaked signed storage URLs — mitigate with short expiry and scoping.
- Credential stuffing / brute force against auth endpoints — mitigate with
  Rack::Attack throttling once configured.
