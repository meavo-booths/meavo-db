#!/usr/bin/env bash
# Prove that a schema change is additive, that the idempotent scripts produce it, and that
# no SQL-only object is added, changed, dropped or forgotten along the way.
#
#   DATABASE_URL=postgresql://user:pass@127.0.0.1:5432/db scripts/verify-sql-replay.sh <base git ref>
#
# Runs in CI (.github/workflows/ci.yml) against a throwaway PostgreSQL service, and
# locally against any disposable database on localhost. It refuses every other host.
#   1. Additive check: `prisma migrate diff` from the base ref's schema to
#      prisma/schema.prisma must contain no DROP, RENAME, SET NOT NULL or type change,
#      except the whole statements listed in REVIEWED below.
#   2. Builds the database from the base ref's schema.
#   3. Applies every script in REPLAY below, in order, twice. A script that is new since
#      the base ref must be listed in REPLAY (or in NOT_REPLAYED, with the reason).
#   4. `prisma migrate diff` from that database to prisma/schema.prisma must be empty,
#      so the scripts create exactly what the schema declares. Prisma ignores the SQL-only
#      objects the scripts also create (CHECK constraints, partial and expression indexes,
#      triggers, functions, sequences); steps 5 and 6 check those against the inventory
#      prisma/sql-only-objects.json (scripts/sql-only-objects.mjs).
#   5. Every SQL-only object the replayed scripts created must be in the inventory with
#      the same definition, and every other inventory entry must be defined by some file
#      in scripts/ (older scripts that only create it together with its table cannot be
#      replayed on a database that already has the table; they are read, not run).
#   6. Rebuilds the database as it was before the change: the base ref's schema plus the
#      SQL-only objects the base ref's inventory records. Applies every REPLAY script once
#      more; the result must again equal prisma/schema.prisma, and its SQL-only objects
#      must equal the inventory exactly. So no script can add, change or drop one, and
#      no entry can be deleted, unless the inventory changes in the same PR.
# A new script is appended to REPLAY in the same PR; a new SQL-only object is added to
# the inventory in the same PR (the failing step prints the line to add).
set -euo pipefail

# Scripts known to be replayable on a database built from the schema, in apply order.
# The first seven are older than the list itself; they were added on 14 November 2026
# because they create SQL-only objects (checks, triggers and their functions, a partial
# index) and replay cleanly.
REPLAY=(
  scripts/client-profile-activity.sql
  scripts/deal-collected-and-labels.sql
  scripts/sales-priority-settings.sql
  scripts/add-sales-deal-id-rename.sql
  scripts/sales-label-campaigns.sql
  scripts/client-merge.sql
  scripts/questionnaire-submission-lat-member.sql
  scripts/add-inventory-v1.sql
  scripts/add-inventory-unit-cost.sql
  scripts/add-inventory-v2-allocation-rules.sql
  scripts/add-inventory-export-lines.sql
  scripts/add-booth-unit-inventory-link.sql
  scripts/add-booth-family-catalog.sql
  scripts/add-production-batch-master.sql
  scripts/add-booth-identity-links.sql
  scripts/add-factory-floor-tables.sql
  scripts/widen-factory-task-override-pk.sql
  scripts/add-mrp-recipe-version-tables.sql
  scripts/add-mrp-electric-assembly-versions.sql
  scripts/align-forecast-fk-and-bom-index-names.sql
  scripts/align-production-drift-2026-11.sql
  scripts/drop-assembly-issue-category.sql
  scripts/relax-inventory-serial-sequence-check.sql
  scripts/sales-discount-rrp.sql
  scripts/sales-product-audit-log.sql
  scripts/sales-label-approvals.sql
  scripts/assembly-submission-edits.sql
  scripts/add-factory-panel-order-cancel-reason.sql
  scripts/add-dev-backlog-tables.sql
  scripts/sales-revenue-targets.sql
  scripts/sales-quote-number-sequence.sql
)

# New scripts that cannot be replayed on a database built from the schema, each with the
# reason. Steps 5 and 6 do not see what these create, so prefer REPLAY.
NOT_REPLAYED=(
)

# Non-additive statements reviewed as unable to lose data, each exactly as
# `prisma migrate diff` prints it with its lines joined by single spaces. Every entry
# names the REPLAY script that performs it; any other DROP, RENAME, SET NOT NULL or
# type change still fails step 1, including a different change to the same object.
REVIEWED=(
  # scripts/widen-factory-task-override-pk.sql: adds the NOT NULL assignedStationId to
  # the primary key, so existing rows stay unique; production already has this key.
  'ALTER TABLE "FactoryScheduleTaskOverride" DROP CONSTRAINT "FactoryScheduleTaskOverride_pkey", ADD CONSTRAINT "FactoryScheduleTaskOverride_pkey" PRIMARY KEY ("batchId", "elementId", "processStep", "assignedStationId");'
  # scripts/align-forecast-fk-and-bom-index-names.sql: re-adds the same foreign key with
  # ON UPDATE NO ACTION (run ids are never updated), as production and staging have it.
  'ALTER TABLE "SalesOpportunityForecastItem" DROP CONSTRAINT "SalesOpportunityForecastItem_runId_fkey";'
  # scripts/align-forecast-fk-and-bom-index-names.sql: renames the unique index to the
  # name production and staging have; same columns, same uniqueness.
  'ALTER INDEX "MrpElementBomLine_recipeVersionId_boothElementId_colour_mar_key" RENAME TO "MrpElementBomLine_recipeVersionId_boothElementId_colour_market_";'
  # scripts/align-production-drift-2026-11.sql: timestamp(3) -> timestamptz, reading the
  # stored UTC values as UTC; no precision is lost. Production already has timestamptz.
  'ALTER TABLE "Deal" ALTER COLUMN "xeroFinalSyncedAt" SET DATA TYPE TIMESTAMPTZ, ALTER COLUMN "xeroPaymentSyncedAt" SET DATA TYPE TIMESTAMPTZ;'
  # scripts/drop-assembly-issue-category.sql: drops the legacy single issue category,
  # replaced by issueCategories in July 2026 and unused since; the 483 production values
  # were exported first on the owner's decision (6 November 2026).
  'ALTER TABLE "Assembly" DROP COLUMN "issueCategory";'
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
inventory=prisma/sql-only-objects.json
prisma="$root/node_modules/.bin/prisma"
[ -x "$prisma" ] || fail "prisma CLI missing: run npm ci in $root"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git -C "$root" show "$base:prisma/schema.prisma" > "$work/base.prisma" || fail "no prisma/schema.prisma at $base"
cd "$root"

echo "---- 1. additive check: $base -> working tree"
"$prisma" migrate diff --from-schema-datamodel "$work/base.prisma" \
  --to-schema-datamodel prisma/schema.prisma --script > "$work/additive.sql"
# One statement per line without comments, so REVIEWED entries match whole statements.
awk '/^--/ || NF == 0 { next }
     { sub(/^[ \t]+/, ""); stmt = (stmt == "" ? $0 : stmt " " $0) }
     /;[ \t]*$/ { print stmt; stmt = "" }
     END { if (stmt != "") print stmt }' "$work/additive.sql" > "$work/statements.sql"
printf '%s\n' ${REVIEWED[@]+"${REVIEWED[@]}"} > "$work/reviewed.txt"
grep -xF -f "$work/reviewed.txt" "$work/statements.sql" | sed 's/^/REVIEWED /' || true
if grep -vxF -f "$work/reviewed.txt" "$work/statements.sql" \
    | grep -nE '(^|[[:space:]])DROP[[:space:]]|RENAME|SET NOT NULL|SET DATA TYPE'; then
  fail "the schema change is not additive (statements above); destructive changes need their own reviewed plan"
fi
grep -E '^-- ' "$work/additive.sql" | sort | uniq -c || true

echo "---- 2. database from the $base schema"
"$prisma" migrate diff --from-empty --to-schema-datamodel "$work/base.prisma" --script > "$work/baseline.sql"
"$prisma" db execute --url "$DATABASE_URL" --file "$work/baseline.sql"

# Applies every REPLAY script, in order, $1 times.
replay() {
  local sql run
  for sql in "${REPLAY[@]}"; do
    for run in $(seq 1 "$1"); do
      "$prisma" db execute --url "$DATABASE_URL" --file "$sql" > /dev/null || fail "$sql (run $run)"
    done
    echo "OK   $sql x$1"
  done
}

# The database must equal prisma/schema.prisma as far as Prisma can see.
schema_diff() {
  local status
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
}

echo "---- 3. replay each script twice"
git ls-tree -r --name-only "$base" -- scripts > "$work/base-scripts.txt"
printf '%s\n' "${REPLAY[@]}" ${NOT_REPLAYED[@]+"${NOT_REPLAYED[@]}"} > "$work/listed.txt"
unlisted=$(ls scripts/*.sql | grep -vxF -f "$work/base-scripts.txt" | grep -vxF -f "$work/listed.txt" || true)
[ -z "$unlisted" ] || fail "new since $base but in neither REPLAY nor NOT_REPLAYED: $(echo $unlisted)"
replay 2

echo "---- 4. replayed database vs prisma/schema.prisma"
schema_diff

echo "---- 5. SQL-only objects the replayed scripts created vs $inventory"
node scripts/sql-only-objects.mjs coverage

echo "---- 6. $base schema and SQL-only objects, every script once more, vs schema and inventory"
printf 'DROP SCHEMA public CASCADE;\nCREATE SCHEMA public;\n' | "$prisma" db execute --url "$DATABASE_URL" --stdin > /dev/null
"$prisma" db execute --url "$DATABASE_URL" --file "$work/baseline.sql" > /dev/null
if git show "$base:$inventory" > "$work/base-inventory.json" 2>/dev/null; then
  echo "     SQL-only objects as $base records them"
else
  cp "$inventory" "$work/base-inventory.json"
  echo "NOTE $base has no $inventory (the change that introduces it): using the working tree's"
fi
node scripts/sql-only-objects.mjs seed --inventory "$work/base-inventory.json"
replay 1
schema_diff
node scripts/sql-only-objects.mjs compare
