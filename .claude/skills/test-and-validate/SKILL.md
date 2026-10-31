---
name: test-and-validate
description: Use as the final validation step before reporting any Lease Intelligence change as complete. Runs the actual, verified quality-gate commands for whichever side(s) of the stack changed and reports real output.
---

# Test and Validate

## Required context

`docs/runbooks/testing.md` for the exact, verified commands — do not
invent a command that "should" exist without confirming it's actually
defined (e.g. check `apps/web/package.json` scripts, check
`apps/api/.github/workflows/ci.yml` for what CI actually runs).

## Workflow

1. Determine which side(s) of the stack changed: `apps/api`, `apps/web`,
   or both.
2. **Backend**, from `apps/api`:
   - `bundle exec rspec` (or `bin/rspec`, once `.rspec`/rspec:install is
     fully configured) — run the full suite or at minimum the specs
     touching the change.
   - `bin/rubocop`
   - `bin/brakeman --no-pager`
3. **Frontend**, from `apps/web`:
   - `npm run build` (typecheck via `tsc -b`, then Vite build)
   - `npm run lint` (oxlint)
4. If migrations were added: `bin/rails db:migrate` then
   `bin/rails db:rollback` to confirm it reverses cleanly, in a
   disposable/test database — never against a database with data you
   can't afford to lose.
5. For tenant-owned data changes: confirm the three-layer isolation test
   (`docs/runbooks/testing.md`) is present and passes.
6. Capture the real output of each command. Do not summarize a command
   as "passed" without having run it in this session.

## Output

A validation report: each command run, its real pass/fail result (with
failure detail if any), and an explicit statement of what was NOT
validated (e.g. "no browser-level test was run for this UI change") so
the user knows the actual boundary of what was checked.
