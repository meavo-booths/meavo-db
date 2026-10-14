#!/usr/bin/env bash
# Apply one idempotent scripts/*.sql file to the staging or production Neon branch.
#
#   scripts/apply-sql.sh staging    scripts/<file>.sql --env-file <file with staging DATABASE_URL> [--diff-only]
#   scripts/apply-sql.sh production scripts/<file>.sql --env-file <file with production DATABASE_URL> --tag vX.Y.Z [--diff-only]
#
# Staging is agent work (RELEASE_POLICY.md): run it twice to prove the script is rerunnable.
# Production is part of an approved meavo-db release: the SQL and schema are read from the
# release tag, which must be on origin/main. The script refuses any other database host,
# prints a before/after diff limited to the identifiers the script touches, and never
# prints the connection string. DATABASE_URL may also come from the environment.
set -euo pipefail

STAGING_HOST=ep-restless-water-apcjwaj4   # Neon branch "staging"
PRODUCTION_HOST=ep-tiny-haze-apqsaah5     # Neon branch "main" = production

fail() { echo "ABORT: $*" >&2; exit 1; }

target=${1:-}; sql=${2:-}
[ "$target" = staging ] || [ "$target" = production ] || fail "first argument must be staging or production"
[ -n "$sql" ] || fail "second argument must be scripts/<file>.sql"
shift 2
env_file=""; tag=""; diff_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) env_file=${2:-}; shift 2;;
    --tag) tag=${2:-}; shift 2;;
    --diff-only) diff_only=1; shift;;
    *) fail "unknown option $1";;
  esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
prisma="$root/node_modules/.bin/prisma"
[ -x "$prisma" ] || fail "prisma CLI missing: run npm install in $root"

if [ -n "$env_file" ]; then
  [ -f "$env_file" ] || fail "env file not found: $env_file"
  DATABASE_URL=$(grep -E '^DATABASE_URL=' "$env_file" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')
fi
[ -n "${DATABASE_URL:-}" ] || fail "no DATABASE_URL (pass --env-file or export it)"
expected=$([ "$target" = staging ] && echo "$STAGING_HOST" || echo "$PRODUCTION_HOST")
case "$DATABASE_URL" in
  *"@$expected"*) echo "OK   target host is $target ($expected)";;
  *) fail "DATABASE_URL is not the $target host $expected";;
esac
export DATABASE_URL

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
if [ "$target" = production ]; then
  [ -n "$tag" ] || fail "production needs --tag vX.Y.Z of the approved release"
  git -C "$root" fetch -q origin main "refs/tags/$tag:refs/tags/$tag" || fail "tag $tag not found on origin"
  commit=$(git -C "$root" rev-list -n1 "$tag")
  git -C "$root" merge-base --is-ancestor "$commit" origin/main || fail "$tag ($commit) is not on origin/main"
  git -C "$root" show "$tag:$sql" > "$work/apply.sql" 2>/dev/null || fail "$sql is not in $tag"
  git -C "$root" show "$tag:prisma/schema.prisma" > "$work/schema.prisma"
  echo "OK   SQL from $tag ($commit)"
else
  [ -f "$root/$sql" ] || fail "$sql not found"
  cp "$root/$sql" "$work/apply.sql"; cp "$root/prisma/schema.prisma" "$work/schema.prisma"
fi
echo "     $sql sha256 $(shasum -a 256 "$work/apply.sql" | cut -d' ' -f1)"

# Identifiers the script names ("Table", "column"), used to keep the diff relevant.
idents=$(grep -v '^[[:space:]]*--' "$work/apply.sql" | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u | paste -sd'|' -)
relevant_diff() {
  "$prisma" migrate diff --from-url "$DATABASE_URL" --to-schema-datamodel "$work/schema.prisma" --script 2>/dev/null \
    | grep -E "${idents:-^$}" || true
}
echo "---- before ($target vs schema, statements touching this script's identifiers):"
before=$(relevant_diff); echo "${before:-<none>}"
[ "$diff_only" = 1 ] && exit 0

echo "---- applying $sql to $target"
"$prisma" db execute --file "$work/apply.sql" --schema "$work/schema.prisma"
after=$(relevant_diff)
echo "---- after:"; echo "${after:-<none>}"
[ -z "$after" ] || echo "NOTE: statements remain; check whether they belong to this script or are older drift." >&2
echo "DONE"
