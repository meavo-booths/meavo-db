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

1. Edit `prisma/schema.prisma` on a `feat/*` branch.
2. Validate: `npm run validate` (needs `DATABASE_URL` in `.env`). Confirm it targets an isolated non-production database.
3. Review the SQL with `npm run diff`; test additive changes there with `npm run db:push`, or reviewed idempotent SQL through `prisma db execute` for ordering-sensitive/destructive changes.
4. Open a PR against `staging` with the SQL, consumer compatibility checks, and rollback notes.
5. Follow [RELEASE_POLICY.md](RELEASE_POLICY.md): obtain specific human approval before production database writes, promotion to `main`, or publishing a release tag/package.
6. Prepare each affected app’s dependency bump as a feature PR against `staging`; production rollout requires its own approval.

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
| Sales | sales | Product, ProductFamilyInfo, Client* (incl. ClientLabel, ClientLabelAssignment, ClientEvent, ClientEventReceipt), Deal* (incl. DealSubscription, DealLabel, DealLabelAssignment), QuoteLineItem, BoothUnit, HubSpotLostReason, HubSpotDealSnapshot, QuotePdfTemplate, QuotePdfMarketDefault, SalesRepIdentity, SalesPriorityRun, SalesPriorityWorkItem, SalesOpportunitySnapshot, SalesCrmSnapshot, SalesCompanyResearch, SalesPriorityRecommendation, SalesPriorityFeedback |
| Notifications | gateway | NotificationOutbox, NotificationDelivery, NotificationEventSetting |
| Manufacturing / MRP | mrp | MrpUserProfile, MrpSupplier*, MrpDocument, MrpLineItem, MrpMaterial, MrpMaterialCategory, MrpStock*, MrpManufacturingBatch, MrpBatchUnit*, MrpRecipeException*, MrpProductionBatch*, MrpInventoryCount, MrpWarehouse, MrpBoothModel, MrpBoothElement, MrpElementBomLine |
| Factory floor & planning | factory | FactoryStation*, FactoryBoothModel, FactoryElement, FactoryColor, FactoryProduction*, FactoryStationWorkItem, FactoryWorkSession, FactoryQuota, FactoryDevice, FactoryCnc*, FactoryPlanning*, FactorySite |
| Spare parts / panels (RP) | rp | RpRequest, RpLineItem, RpInternalProductionRow, RpPhoto, RpSheetSyncOutbox, RpSheetRowMap, RpAddressBookEntry, RpPanelCatalogOption, RpExportTrackingRow, RpNumSequence, RpIpNumSequence, RpAutomationState, RpLifecycleEvent, RpPartMrpMap, RpPanelMrpMap, RpSparePart, RpPanelOption |
| Task management | tasks | TaskWorkspace, TaskWorkspaceMember, TaskBoardColumn, Task, TaskAssignee, TaskExternalLink |
| Feature requests | requests | FeatureRequest, FeatureRequestVote |

Other apps may **read** tables they don't own (e.g. gateway reads assembly
counts for tool-card stats) but should only **write** through the owner app.

## Documentation

| Doc | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Quick orientation for AI coding agents |
| [.cursor/rules/](.cursor/rules/) | Always-on Cursor rules |
| [docs/data-model.md](docs/data-model.md) | Domains, ownership, migration safety |
| [docs/architecture.md](docs/architecture.md) | Consumption model and release flow |
| [CONTRIBUTING.md](CONTRIBUTING.md) | PR and release process |
