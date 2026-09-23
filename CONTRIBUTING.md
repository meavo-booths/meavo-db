<!-- BEGIN MEAVO RELEASE POLICY -->
## Branches and production permission

Create `feat/`, `fix/`, or `chore/` branches from `staging` and open PRs explicitly into `staging`; squash after required checks pass. Never push directly to `main` or `staging`. Production releases use a `staging` → `main` PR and a merge commit. AI agents require explicit human authorization for the repository, production action, and current reviewed PR/head SHA or artifact/configuration scope before merging, enabling auto-merge, queueing, or making any production change. See [RELEASE_POLICY.md](RELEASE_POLICY.md) for the mandatory approval and environment checks; missing staging does not authorize a main release.
<!-- END MEAVO RELEASE POLICY -->

# Contributing — meavo-db

## Before you open a PR

- [ ] Changes are scoped to the request — no drive-by refactors of other apps' sections
- [ ] `npm run validate` passes
- [ ] `npm run diff` output reviewed — no unexpected `DROP` statements (no test suite; this is the safety net)
- [ ] Agent docs updated if you added a new domain section or changed the release workflow
- [ ] Destructive steps shipped as idempotent `scripts/*.sql`, not through `db:push`

## Branch naming and release path

Use `feat/short-description` for agent work and open PRs with an explicit `staging` base. Validate the feature preview and staging before preparing a release. Follow [RELEASE_POLICY.md](RELEASE_POLICY.md): changes to `main`, production deployments/migrations, and release tags require specific human approval for the action and revision.

If `staging` or its safe preview environment is missing, prepare feature-only changes and report the setup gap; do not substitute `main`.

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

1. Edit `prisma/schema.prisma` on `feat/*`; run `npm run validate` and `npm run diff` against an isolated non-production database and review the SQL.
2. Test additive changes with `npm run db:push`; test destructive or ordering-sensitive changes with reviewed idempotent `scripts/*.sql` through `prisma db execute`. Confirm the database target before either command.
3. Submit the version/schema changes to `staging`, with SQL, compatibility checks, and rollback notes. A passing staging check is not permission to apply to the shared production database.
4. Obtain specific human approval under [RELEASE_POLICY.md](RELEASE_POLICY.md) before each production migration, `main` promotion, or release-tag/package publication.
5. Prepare dependency bumps as feature PRs to `staging` in affected apps; each production rollout needs its own approval.

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
