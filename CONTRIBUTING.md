# Contributing — meavo-db

## Before you open a PR

- [ ] Changes are scoped to the request — no drive-by refactors of other apps' sections
- [ ] `npm run validate` passes
- [ ] `npm run diff` output reviewed — no unexpected `DROP` statements (no test suite; this is the safety net)
- [ ] Agent docs updated if you added a new domain section or changed the release workflow
- [ ] Destructive steps shipped as idempotent `scripts/*.sql`, not through `db:push`

## Branch naming

`feature/short-description`, `fix/short-description`, `docs/short-description`. Small schema changes are often committed directly to `main` by the maintainer — follow the existing history.

## Commit messages

Imperative sentence naming the schema change and the app it serves, e.g. "Add task management schema for tasks.meavo.app".

## Code placement

| Layer | Location |
|-------|----------|
| Data model | `prisma/schema.prisma`, inside the owning app's `// ---- ... ----` section |
| Targeted / destructive migrations | `scripts/*.sql` (idempotent, with an `-- Apply:` header) |
| Ownership matrix | `README.md` |
| Agent / domain docs | `docs/`, `AGENTS.md` |

No app code, seeds, or generated client output belongs in this repo.

## Cross-repo dependencies

This repo is the dependency. After a release, bump the `@meavo/db` git ref in each affected app's `package.json`, run `npm install` (triggers `prisma generate`), and redeploy.

## Schema changes

All schema changes happen **here** — never in app repos:

1. Edit `prisma/schema.prisma` → `npm run validate` → `npm run diff` (read the SQL).
2. Apply: `npm run db:push` for additive changes; `prisma db execute --file scripts/<file>.sql` for destructive ones.
3. Commit, bump `version` in `package.json`, `git tag v0.x.y && git push --tags`.
4. Bump the ref in consuming apps.

## PR description

Include:

1. **What** changed (models/fields/enums, which app's section)
2. **Why** (link the consumer-app issue or PR if any)
3. **How to verify** (`npm run diff` output summary)
4. **Out of scope** (data backfill, consumer-app code, etc.)

## Agent-assisted PRs

If an AI agent wrote the change:

- Verify section placement and ownership against `docs/data-model.md` and `README.md`
- Reject leftover template placeholder comments in merged files
- Ensure no secrets in diff and no accidental edits to other apps' models
