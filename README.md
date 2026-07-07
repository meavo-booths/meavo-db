# @meavo/db

Canonical Prisma schema for the shared MEAVO Postgres (Neon) database used by:

- **meavo-gateway** — identity, tool cards, HR, documents, library, notifications
- **Vacation Tracker (hols)** — vacation requests, allowances, public holidays
- **meavo-assembly** — assemblies, partners, questionnaires, resources
- **meavo-sales** — clients, deals, quotes, products, booth units
- **meavo-rp** — spare-parts / panel requests, internal production, sheet sync

## The rule

**This is the only repository allowed to alter the database schema.**

The app repos consume this package as a git dependency and run `prisma generate`
only. Their `db:push` scripts are disabled on purpose: pushing from an app's
partial schema would drop the other apps' tables and columns.

## Making a schema change

1. Edit `prisma/schema.prisma` here.
2. Validate: `npm run validate` (needs `DATABASE_URL` in `.env`).
3. Preview the SQL against the live DB:
   `npx prisma migrate diff --from-schema-datasource prisma/schema.prisma --to-schema-datamodel prisma/schema.prisma --script`
4. Apply with `npm run db:push` (or targeted SQL via `prisma db execute` for
   anything destructive).
5. Commit, tag a new version (`git tag v0.x.y && git push --tags`).
6. Bump the `@meavo/db` dependency ref in each app that needs the new models
   and redeploy.

## How apps consume it

Each app's `package.json` contains:

```json
{
  "dependencies": {
    "@meavo/db": "git+https://github.com/meavo-booths/meavo-db.git#v0.1.0"
  },
  "prisma": {
    "schema": "node_modules/@meavo/db/prisma/schema.prisma"
  }
}
```

`prisma generate` (run on postinstall and in builds) then generates the client
from the canonical schema. Apps keep their own `prisma/seed.ts`.

## Table ownership

| Domain | Owner app | Tables |
| --- | --- | --- |
| Identity & access | gateway | User, Account, Team, TeamMember, ToolCard, ToolCardAccess, LoginThrottle |
| HR & documents | gateway | CompanyProfile, Employee, EmployeeSalaryHistory, EmployeeDocument, DocumentTemplate*, GeneratedDocument, LibraryAsset, GatewaySheetRecord |
| Vacation | hols | VacationRequest, UserAllowance, PublicHoliday |
| Assembly | assembly | Assembly, AssemblyPartner, Questionnaire*, Question*, Submission*, Resource*, SheetImportState |
| Sales | sales | Product, Client*, Deal*, QuoteLineItem, BoothUnit |
| Notifications | gateway | NotificationOutbox, NotificationDelivery, NotificationEventSetting |
| Manufacturing / MRP | mrp | MrpUserProfile, MrpSupplier*, MrpDocument, MrpLineItem, MrpMaterial, MrpStock*, MrpManufacturingBatch, MrpBatchUnit*, MrpRecipeException*, MrpProductionBatch*, MrpInventoryCount, MrpWarehouse, MrpBoothModel, MrpBoothElement, MrpElementBomLine |
| Factory floor & planning | factory | FactoryStation*, FactoryBoothModel, FactoryElement, FactoryColor, FactoryProduction*, FactoryStationWorkItem, FactoryWorkSession, FactoryQuota, FactoryDevice, FactoryCnc*, FactoryPlanning*, FactorySite |
| Spare parts / panels (RP) | rp | RpRequest, RpLineItem, RpInternalProductionRow, RpPhoto, RpSheetSyncOutbox, RpSheetRowMap, RpAddressBookEntry, RpPanelCatalogOption, RpExportTrackingRow, RpNumSequence, RpIpNumSequence, RpAutomationState |

Other apps may **read** tables they don't own (e.g. gateway reads assembly
counts for tool-card stats) but should only **write** through the owner app.
