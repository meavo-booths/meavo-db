# Architecture — meavo-db (@meavo/db)

Schema-only npm package holding the canonical Prisma schema for the one shared MEAVO Neon Postgres database. No production URL — the "deployment" is a git tag consumed by the app repos.

**Further reading:**
- [data-model.md](data-model.md) — domains, ownership, migration safety (primary doc)
- [AGENTS.md](../AGENTS.md) — quick orientation for AI agents
- [factory-audit.md](factory-audit.md) — Meavo-Factory Supabase → Neon migration audit

## Sibling repos (meavo-booths)

Every app in the org consumes this package; none may alter the schema themselves.

| Repo | Relationship |
|------|--------------|
| `meavo-gateway` | Owns identity, HR, documents, notifications sections; reference implementation for org standards |
| `hols` | Owns vacation section |
| `assembly` | Owns assembly/questionnaire sections |
| `sales` | Owns sales + Xero sections |
| `meavo-mrp` | Owns MRP section |
| `Meavo-Factory` | Owns factory floor + planning sections (migrated from Supabase — see factory-audit.md) |
| `meavo-rp` | Owns RP spare-parts section (legacy snake_case tables via `@@map`) |
| `meavo-clock` | Owns Clock-In section |
| `meavo-tasks` | Owns task management section |
| `meavo-agent-templates` | Org-wide standards these docs follow |

## Stack decisions

- **Prisma 6, single schema file** — one source of truth prevents an app's partial schema from dropping other apps' tables on push.
- **Git-tag distribution instead of npm registry** — apps pin `git+https://github.com/meavo-booths/meavo-db.git#v0.x.y` and point Prisma at `node_modules/@meavo/db/prisma/schema.prisma`; no publish pipeline needed.
- **`db push` + idempotent SQL scripts instead of Prisma migrations** — the DB predates this repo and is shared; targeted `scripts/*.sql` via `prisma db execute` handle anything `db push` can't do safely.

## Repository layout

```
prisma/schema.prisma   # the entire data model, sectioned by owning app
scripts/*.sql          # idempotent targeted migrations (prisma db execute)
docs/                  # data-model, architecture, one-off audits
README.md              # table ownership matrix + change workflow
package.json           # version = release tag; prisma is the only dependency
```

## Data flow

```
schema edit → validate → diff (review SQL) → db:push / db execute → live Neon DB
     └→ commit → version bump → git tag v0.x.y → push --tags
            └→ each affected app bumps @meavo/db ref → npm install → prisma generate → redeploy
```

## API surface

N/A — schema package only. The npm scripts (`validate`, `diff`, `db:push`, `studio`) are the whole interface.

## Scheduled jobs

N/A.

## Environment variables

Document names only:

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Shared Neon Postgres connection string (same DB as gateway) — needed for `validate`, `diff`, `db:push`, `studio` |

## Deployment

None. Releases are git tags; consuming apps redeploy (Vercel) after bumping their `@meavo/db` ref.
