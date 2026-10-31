---
name: security-review
description: Use before shipping any change touching authentication, authorization, file access, secrets, or external AI/OCR provider calls on Lease Intelligence. Produces a structured security review, not a fix.
---

# Security Review

## Required context

Root `CLAUDE.md` §9, `docs/architecture/security.md`,
`.claude/rules/security.md`, `.claude/agents/security-engineer.md`. Then
read the actual diff/code under review.

## Workflow

1. Identify what changed: new endpoint, new file-access path, new
   external provider call, new auth/authz logic, new secret/credential
   usage.
2. For authorization: confirm a Pundit policy exists and is exercised for
   every new action; confirm the policy has both an allow and a deny
   test.
3. For file access: confirm storage is private, URLs are short-lived and
   scoped, no permanent public link is created or logged.
4. For external provider calls (OCR/LLM/storage): confirm credentials
   come from encrypted credentials/env vars, confirm provider failures
   are handled without leaking internal error detail to the client,
   confirm document content isn't logged.
5. For AI/LLM calls specifically: confirm document content is
   structurally separated from system instructions in the prompt, per
   `.claude/rules/ai-processing.md`.
6. For logging: grep the diff for anything that could log contract
   content, personal data, secrets, or tokens.
7. Check for the specific anti-patterns root `CLAUDE.md` §4 forbids:
   disabled RLS, trusted frontend tenant IDs, business rules in
   controllers used as an authorization shortcut, undocumented
   cross-tenant bypasses.

## Output

A structured finding list: for each issue, the concrete failure scenario
(what input/state leads to what exposure), severity, and the specific
change required. If nothing is found, say so explicitly rather than
omitting a section — "reviewed X, no issues found" is a valid and useful
output.
