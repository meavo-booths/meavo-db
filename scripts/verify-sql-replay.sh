#!/usr/bin/env bash
# Prove that a schema change is additive and that the idempotent scripts produce it.
#
#   DATABASE_URL=postgresql://user:pass@127.0.0.1:5432/db scripts/verify-sql-replay.sh <base git ref>
#
# Runs in CI (.github/workflows/ci.yml) against a throwaway PostgreSQL service, and
# locally against any disposable database on localhost. It refuses every other host.
#   1. Additive check: `prisma migrate diff` from the base ref's schema to
#      prisma/schema.prisma must contain no DROP, RENAME, SET NOT NULL or type change.
#   2. Builds the database from the base ref's schema.
#   3. Applies every script in REPLAY below, in order, twice.
#   4. `prisma migrate diff` from that database to prisma/schema.prisma must be empty,
#      so the scripts create exactly what the schema declares (Prisma ignores the
#      SQL-only checks and partial or expression indexes the scripts also create).
# A new script that ships a schema change is appended to REPLAY in the same PR.
set -euo pipefail

# Scripts known to be replayable on a database built from the schema, in apply order.
REPLAY=(
  scripts/add-inventory-v1.sql
  scripts/add-inventory-unit-cost.sql
  scripts/add-inventory-v2-allocation-rules.sql
  scripts/add-inventory-export-lines.sql
  scripts/add-booth-unit-inventory-link.sql
  scripts/add-booth-family-catalog.sql
  scripts/add-production-batch-master.sql
  scripts/add-booth-identity-links.sql
  scripts/add-factory-floor-tables.sql
)

fail() { echo "FAIL: $*" >&2; exit 1; }

base=${1:-}
[ -n "$base" ] || fail "usage: scripts/verify-sql-replay.sh <base git ref>"
[ -n "${DATABASE_URL:-}" ] || fail "DATABASE_URL must point at a disposable local database"
case "$DATABASE_URL" in
  *@127.0.0.1:*|*@127.0.0.1/*|*@localhost:*|*@localhost/*) ;;
  *) fail "refusing a DATABASE_URL that is not on localhost or 127.0.0.1";;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
prisma="$root/node_modules/.bin/prisma"
[ -x "$prisma" ] || fail "prisma CLI missing: run npm ci in $root"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git -C "$root" show "$base:prisma/schema.prisma" > "$work/base.prisma" || fail "no prisma/schema.prisma at $base"
cd "$root"

echo "---- 1. additive check: $base -> working tree"
"$prisma" migrate diff --from-schema-datamodel "$work/base.prisma" \
  --to-schema-datamodel prisma/schema.prisma --script > "$work/additive.sql"
if grep -nE '(^|[[:space:]])DROP[[:space:]]|RENAME|SET NOT NULL|SET DATA TYPE' "$work/additive.sql"; then
  fail "the schema change is not additive (statements above); destructive changes need their own reviewed plan"
fi
grep -E '^-- ' "$work/additive.sql" | sort | uniq -c || true

echo "---- 2. database from the $base schema"
"$prisma" migrate diff --from-empty --to-schema-datamodel "$work/base.prisma" --script > "$work/baseline.sql"
"$prisma" db execute --url "$DATABASE_URL" --file "$work/baseline.sql"

echo "---- 3. replay each script twice"
for sql in "${REPLAY[@]}"; do
  for run in 1 2; do
    "$prisma" db execute --url "$DATABASE_URL" --file "$sql" > /dev/null || fail "$sql (run $run)"
  done
  echo "OK   $sql x2"
done

echo "---- 4. replayed database vs prisma/schema.prisma"
set +e
"$prisma" migrate diff --from-url "$DATABASE_URL" --to-schema-datamodel prisma/schema.prisma \
  --script --exit-code > "$work/remaining.sql"
status=$?
set -e
if [ "$status" -eq 2 ]; then
  cat "$work/remaining.sql"
  fail "the replayed scripts do not produce prisma/schema.prisma (statements above); add or fix a script and list it in REPLAY"
fi
[ "$status" -eq 0 ] || fail "prisma migrate diff exited with $status"
echo "OK   no difference"
