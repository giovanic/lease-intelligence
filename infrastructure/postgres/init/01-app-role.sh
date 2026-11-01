#!/bin/sh
# Runs once, when the volume is created. The application role must never be
# a superuser nor bypass RLS (docs/adr/0003, .claude/rules/database.md):
# FORCE ROW LEVEL SECURITY only proves something for a role like this.
# CREATEDB lets `bin/rails db:prepare` create the dev and test databases.
set -eu

psql -v ON_ERROR_STOP=1 --username postgres <<SQL
CREATE ROLE lease_intelligence LOGIN PASSWORD '${LEASE_INTELLIGENCE_DATABASE_PASSWORD}' NOSUPERUSER NOBYPASSRLS CREATEDB;
SQL

privileged=$(psql --username postgres -tAc "SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname = 'lease_intelligence'")
test "$privileged" = "f" || { echo "lease_intelligence must not be superuser or bypass RLS" >&2; exit 1; }
