---
name: implement-feature
description: Use when implementing a non-trivial business feature on Lease Intelligence (anything beyond a one-line fix). Walks the standard 12-step workflow from requirement analysis to completion report, coordinating the other skills/agents as needed.
---

# Implement Feature

## Required context

Root `CLAUDE.md`, the relevant `docs/product/*.md`, the relevant
`docs/architecture/*.md` and `docs/domain/*.md`, any ADR touching the
feature's area, and the current code in the affected domain (never assume
docs are up to date — verify).

## Workflow

0. **Branch** — if this starts a new phase, create a new branch from an
   up-to-date `main` (`feat/<short-kebab-name>`, `fix/<name>` for bug
   fixes) before any change. Commit as `feat: <resumo do que foi implementado>`. Never start a phase on `main` or
   on the previous phase's branch.
1. **Requirement analysis** — restate the actual requirement in your own
   words; identify ambiguity and resolve it with the user before
   proceeding if it would change the design.
2. **Product documentation review** — read `docs/product/` for how this
   feature fits the product vision/scope. Confirm it's in MVP scope
   (`docs/product/mvp-scope.md`) or get explicit confirmation it's an
   intentional exception.
3. **Existing code inspection** — read the actual current state of the
   affected domain; don't rely on a prior session's summary.
4. **Domain identification** — name the domain(s) involved
   (`docs/domain/`); if it spans domains, note the boundary explicitly.
5. **Architecture impact analysis** — does this touch a documented
   pattern (versioning, tenancy, provider abstraction)? If it requires a
   new architectural decision, stop and invoke `architecture-decision`
   before proceeding.
6. **Security and tenant isolation assessment** — is this tenant-owned
   data? Does it need Pundit policies? Does it touch file access, auth,
   or AI providers? If yes to any, this needs `security-engineer` review
   before being considered done — use the `security-review` and/or
   `tenant-isolation-review` skill as applicable.
7. **Implementation planning** — write a short plan: files to touch,
   migrations needed, service objects, API endpoints, frontend
   components. For architectural changes identified in step 5, get the
   ADR reviewed/approved before writing code.
8. **Test planning** — identify required coverage per
   `docs/runbooks/testing.md` before writing implementation code.
9. **Implementation** — follow existing patterns
   (`.claude/rules/backend.md`, `.claude/rules/frontend.md`, etc.). No
   unrelated refactoring.
10. **Automated validation** — use the `test-and-validate` skill; actually
    run the commands, don't assume.
11. **Documentation updates** — update the relevant `docs/` files and ADR
    implementation-status fields if this changed the actual implemented
    state.
12. **Completion report** — what changed, what was validated (with real
    command output), what risks/follow-ups remain.

## Output

A completed, tested change plus a completion report following step 12's
shape. Never report completion without having actually run validation.
