---
applies_to: apps/api/spec/**, apps/web/**
---

# Testing Rules

See `docs/runbooks/testing.md` for exact, verified commands.

- Every business feature ships with automated tests: models, policies,
  services, API request specs — whichever apply. A feature is not done
  because the happy path works (root `CLAUDE.md` §13).
- Security-sensitive features test both the permitted and the denied
  path explicitly. A policy spec that only covers "allowed" is
  incomplete.
- Tenant-owned data changes require the three-layer isolation test:
  policy-level deny test, request-level cross-tenant test, and a
  raw-SQL-level RLS test that bypasses application authorization
  entirely (proving the database itself refuses the row).
- Background jobs: test idempotency (running twice doesn't double-create/
  double-charge) and tenant-context handling (job fails loudly with no
  context, succeeds correctly with one).
- Financial calculations: test decimal precision/rounding explicitly,
  never assume floating-point-style approximation is acceptable.
- Never delete or skip a failing test to make a build pass. If the test
  itself is wrong, say so explicitly and get agreement before removing
  it.
- Never report `bin/rspec`, `bin/rubocop`, `bin/brakeman`, `npm run
  build`, or `npm run lint` as passing without having actually run them
  via Bash in this session and read the real output.
- Decide and standardize on one backend test framework — `apps/api`
  currently has both RSpec (`spec/`, gems installed) and the Rails
  default Minitest (`test/`, still present, empty) side by side; this is
  a known duplication to resolve, not a pattern to continue.
