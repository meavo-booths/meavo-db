# Data model — meavo-db

The canonical schema lives **in this repo**: `prisma/schema.prisma` (~125 models, ~54 enums). This is the only repo allowed to alter the shared MEAVO Neon Postgres database; every app repo consumes it read-only via the `@meavo/db` git dependency and runs `prisma generate` only.

Pinned version: apps pin a git tag, e.g. `"@meavo/db": "git+https://github.com/meavo-booths/meavo-db.git#v0.13.0"` — current version in `package.json`.

## Domains (schema sections)

The schema is organized by owning app with `// ---- <Domain> (owner: <app>) ----` comments. Owners write their tables; other apps may read but write only through the owner app.

| Schema section | Owner app | Representative models |
|----------------|-----------|-----------------------|
| Identity & access | gateway | `User`, `Account`, `Team`, `TeamMember`, `ToolCard`, `ToolCardAccess`, `LoginThrottle` |
| HR & documents | gateway | `Employee`, `EmployeeSalaryHistory`, `DocumentTemplate*`, `GeneratedDocument`, `LibraryAsset`, `GatewaySheetRecord` |
| Vacation tracking | hols | `VacationRequest`, `UserAllowance`, `PublicHoliday` |
| Assembly | assembly | `Assembly`, `AssemblyPartner`, `Questionnaire*`, `QuestionnaireSubmission`, `Resource*`, `SheetImportState` |
| Sales | sales | `Product`, `Client`, `Deal`, `QuoteLineItem`, `BoothUnit` |
| Xero integration | sales | `XeroMarketThemeMapping`, `XeroMarketTaxMapping`, `XeroMarketAccountMapping`, `XeroIntegrationSettings` |
| Notifications | gateway | `NotificationOutbox`, `NotificationDelivery`, `NotificationEventSetting` |
| Manufacturing / MRP | mrp | `MrpDocument`, `MrpLineItem`, `MrpMaterial`, `MrpManufacturingBatch`, `MrpElementBomLine`, ... |
| Factory floor + planning | factory | `FactoryStation*`, `FactoryProduction*`, `FactoryPlanning*`, `FactoryDevice`, `FactoryCnc*` |
| RP spare parts / panels | rp | `RpRequest`, `RpLineItem`, `RpInternalProductionRow`, `RpSheetSyncOutbox`, `RpLifecycleEvent`, ... |
| Clock-In | clock | clock-in / time-tracking models (see `scripts/add-clock-tables.sql`) |
| Task management | tasks | `TaskWorkspace`, `TaskBoardColumn`, `Task`, `TaskAssignee`, `TaskExternalLink` |
| Feature requests | requests | `FeatureRequest`, `FeatureRequestVote` (`FeatureRequestType`, `FeatureRequestImportance`) |

The full authoritative matrix is in [README.md](../README.md) § Table ownership.

## Entity relationship (identity spine)

```
User ──< TeamMember >── Team
 │ ──< Account                      (OAuth)
 │ ──< ToolCardAccess >── ToolCard  (per-app access gating, kind APP_ACCESS)
 │ ──< VacationRequest / Deal / Task / Mrp* / Rp* ...   (domain FKs from every app)
```

All satellite domains foreign-key to the shared `User` / `Team` — never duplicate identity tables.

## Naming & style

- PascalCase models, camelCase fields, `cuid()` string IDs, `SCREAMING_SNAKE` enum values.
- Domains ported from legacy systems (RP, some MRP/Factory tables) keep their original snake_case table names via `@@map` / `@map` — keep that mapping intact when editing them.
- New models go inside their owner's `// ---- ... ----` section; a new app gets a new section at the end plus a row in README's ownership table.
- New satellite apps also need: a `ToolCard` seed in gateway (kind `APP_ACCESS`, stable `seed-<app>-tool` ID) and notification event types in gateway's event catalog — those live in the gateway repo, not here.

## Applying changes (migration safety)

There is **no Prisma migrations directory** — the workflow is `db push` against the live shared DB:

1. Edit `prisma/schema.prisma`; `npm run validate`.
2. `npm run diff` — **read the generated SQL**. Anything with `DROP` needs to be understood before going further; a stale or trimmed schema will drop other apps' tables.
3. Additive changes: `npm run db:push`.
4. Destructive or ordering-sensitive changes: write an **idempotent** script in `scripts/` (wrap `CREATE TYPE` etc. in `DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL`), with an `-- Apply:` header, and run `npx prisma db execute --file scripts/<file>.sql --schema prisma/schema.prisma`. See `scripts/add-task-tables.sql` for the pattern.
5. Commit, bump `version` in `package.json`, `git tag v0.x.y && git push --tags`, then bump the `@meavo/db` ref in each affected app and redeploy.

Consumer apps must **never** run `db:push` themselves — their partial schemas would drop everyone else's tables.

## Sync / external copies

Several domains mirror rows to Google Sheets or queue side effects; the outbox/state tables live here, the sync code lives in the owning app:

- `NotificationOutbox` / `NotificationDelivery` — satellites enqueue, gateway sends email.
- `RpSheetSyncOutbox`, `RpSheetRowMap`, `SheetImportState`, `GatewaySheetRecord` — sheet sync state for rp / assembly / gateway.

## Queries agents should reuse

N/A — this repo contains no query code. Prisma client helpers, seeds, and repositories live in the consuming apps.
