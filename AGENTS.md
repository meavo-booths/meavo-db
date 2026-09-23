<!-- BEGIN MEAVO RELEASE POLICY -->
## Release safety — mandatory for all AI agents

- Default scope: create `feat/`, `fix/`, or `chore/` branches from `staging`; use PRs into `staging` and squash only after required checks pass.
- Do not merge to `main`, enable auto-merge/queue a production PR, or change production without **explicit human approval for this repository, the specific action, and the reviewed PR/head SHA or exact artifact/configuration scope**. Changed scope or head invalidates approval; never infer or generate it. Reuse still-valid approval without asking again.
- Never push directly to `main`/`staging` or bypass protections. Missing `staging` is not permission to use `main`.
- Read [RELEASE_POLICY.md](RELEASE_POLICY.md) before any release, deployment, environment, schema, or tag/package publication action. Verify actual environment destinations before writes.
<!-- END MEAVO RELEASE POLICY -->

# Agent guide — meavo-db

Quick orientation for AI agents working in this repo. Read this before exploring blindly.

**Cursor:** `.cursor/rules/core.mdc` and `.cursor/rules/security.mdc` are always applied.

## What this repo does

`@meavo/db` is the canonical Prisma schema for the **one shared Neon Postgres database** used by every MEAVO app (gateway, hols, assembly, sales, mrp, factory, rp, clock, tasks). **This is the only repository allowed to alter the database schema.** App repos consume it as a git dependency and run `prisma generate` only.

## Stack

- Prisma 6 schema (`prisma/schema.prisma`) targeting PostgreSQL (Neon) — ~125 models, ~54 enums
- Plain npm package, no app code: published via git tags, consumed as `git+https://github.com/meavo-booths/meavo-db.git#v0.x.y`
- Targeted/destructive changes: idempotent SQL in `scripts/*.sql` applied with `prisma db execute`
- No framework, no tests, no lint, no deploy — the "release" is a git tag

## First files to read

| Task | Start here |
|------|------------|
| Change a model for an existing app | `prisma/schema.prisma` — find the `// ---- <Domain> (owner: <app>) ----` section |
| Find which app owns a table | `README.md` § Table ownership |
| Add a new app's domain | `prisma/schema.prisma` (new owner section at the end) + `README.md` ownership table |
| Validate the schema | `npm run validate` (needs `DATABASE_URL` in `.env`) |
| Preview SQL against the live DB | `npm run diff` |
| Apply schema to an environment | Confirm the database target; test in isolation first. Production writes require specific human approval under [RELEASE_POLICY.md](RELEASE_POLICY.md) and the SQL review in [docs/data-model.md](docs/data-model.md) |
| Destructive / targeted migration | idempotent SQL like `scripts/add-task-tables.sql`, via `prisma db execute` |
| Release + consumer bump process | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Factory app migration context | `neon-migration-audit.md` in the private Meavo-Factory repo (not in this repo) |
| Auth & access | N/A — no runtime code; identity models live in the gateway section of the schema |
| DB schema | `prisma/schema.prisma` (this repo IS the owner) |
| Tests | N/A — `npm run validate` + `npm run diff` are the safety net |

## Do NOT

- Do NOT run `prisma migrate dev` or add a migrations directory — this repo uses `db push` plus idempotent `scripts/*.sql` only.
- Do NOT run `db:push` casually: the DB is shared by all apps, and pushing after removing/renaming models **drops other apps' live tables or columns**. Always run `npm run diff` first and read the SQL.
- Do NOT rename or delete another app's models, fields, or enums without checking every consumer app (see ownership table in `README.md`).
- Do NOT duplicate `User` / `Team` style identity tables for a new domain — foreign-key to the shared gateway models.
- Do NOT add app code, seed data, or generated Prisma client output here — schema + SQL scripts only; each app keeps its own seed script.
- Do NOT commit `.env` or any secret; only `DATABASE_URL`'s *name* is documented.
- Do NOT publish a tag just to test a consumer. Production dependencies use approved release tags; an immutable staging commit may be used only for documented, non-production validation under `RELEASE_POLICY.md`.

## Commands

```bash
npm install          # installs prisma CLI (only dev dependency)
npm run validate     # prisma validate (needs DATABASE_URL in .env)
npm run diff         # SQL preview: live DB vs schema.prisma
npm run db:push      # confirm isolated test DB; production requires specific human approval
npm run studio       # browse the live DB
# no dev / test / lint / build — this is a schema-only package
```

## Conventions

1. Schema is organized by owning app with `// ---- <Domain> (owner: <app>) ----` section comments; new models go inside their owner's section.
2. Naming: PascalCase models, camelCase fields, `cuid()` string IDs, `SCREAMING_SNAKE` enum values. Ported legacy tables keep their snake_case names via `@@map` / `@map`.
3. Prepare schema/version changes on `feat/*` → `validate` → review `diff` and test against an isolated non-production DB → PR to `staging`. Obtain specific human approval under `RELEASE_POLICY.md` before production SQL, `main` promotion, or tag/package publication. Prepare consumer dependency bumps through their own feature/staging workflow.
4. Destructive or data-migrating steps go in an idempotent `scripts/*.sql` (`DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL`) with an "Apply:" comment header, not through `db push`.
5. Commit messages: imperative sentence describing the schema change and the app it serves, e.g. "Add task management schema for tasks.meavo.app".

## Scoped task template (preferred from user)

```
App/domain: [e.g. sales / Deal]
Behaviour: [what the schema change should enable]
Reference: [consumer-app PR or issue, if any]
Out of scope: [other apps' tables, data backfill, etc.]
```

## Related docs

- [docs/data-model.md](docs/data-model.md) — domains, ownership, migration safety (primary doc)
- [docs/architecture.md](docs/architecture.md) — how apps consume this package, release flow
- [CONTRIBUTING.md](CONTRIBUTING.md) — PR + release process
- [README.md](README.md) — table ownership matrix
