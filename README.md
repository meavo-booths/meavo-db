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
4. Open a PR against `staging` with the SQL, consumer compatibility checks, and rollback notes. CI (`Validate schema`) rejects a non-additive diff from the base branch (except whole statements reviewed in the script's `REVIEWED` list, each performed by a listed script), replays every script listed in `scripts/verify-sql-replay.sh` twice on a database built from the base schema, and requires the result to equal `prisma/schema.prisma`; list a new script there in the same PR. It also checks the objects Prisma cannot see against [prisma/sql-only-objects.json](prisma/sql-only-objects.json) (see [SQL-only objects](#sql-only-objects)). Run it locally with `DATABASE_URL=<disposable localhost database> scripts/verify-sql-replay.sh origin/staging`.
5. Follow [RELEASE_POLICY.md](RELEASE_POLICY.md): the only human gate is the staging → `main` release; its yes also covers the release tag and the release's production SQL.
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
| Identity & access | gateway | User, Account, Team, TeamSubgroup, TeamMember, GatewayUserImportReceipt, ToolCard, ToolCardAccess, LoginThrottle |
| HR & documents | gateway | CompanyProfile, Employee, EmployeeSalaryHistory, EmployeeCommission, EmployeeDocument, DocumentTemplate*, GeneratedDocument, SignatureRequest, LibraryAsset, LibraryVideo, UsefulLink, GatewaySheetRecord |
| Vacation | hols | VacationRequest, UserAllowance, PublicHoliday |
| Assembly | assembly | Assembly, AssemblyPartner, AssemblyTeam, AssemblyTeamMember, AssemblyTeamAssignment, PartnerNotificationPreference, Questionnaire*, Question*, Submission*, Resource*, SheetImportState |
| Sales | sales | Product, ProductAuditLog, ProductFamilyInfo, ProductAvailability, ProductAddOnFamilyRestriction, Client* (incl. ClientLabel, ClientLabelAssignment, ClientEvent, ClientEventReceipt, ClientMergeAudit), Deal* (incl. DealSubscription, DealLabel, DealLabelAssignment, DealLabelApprovalRequest), QuoteLineItem, BoothUnit, SalesPayment, SalesPaymentWindow, SalesPaymentSync, HubSpotLostReason, HubSpotDealSnapshot, HubSpotMarketingSync, HubSpotMarketingForm, HubSpotMarketingSubmission, HubSpotCampaignSyncState, QuotePdfTemplate, QuotePdfMarketDefault, SalesRepIdentity, SalesPrioritySettings, SalesPriorityRun, SalesPriorityWorkItem, SalesOpportunitySnapshot, SalesCrmSnapshot, SalesCompanyResearch, SalesPriorityRecommendation, SalesPriorityFeedback, SalesForecastSettings, SalesForecastRun, SalesForecastManualRun, SalesOpportunityForecastRun, SalesOpportunityForecastItem, SalesOpportunityQualification, SalesOpportunityQualificationEvent, SalesRevenueTarget; the sequence `SalesQuoteNumberSeq` (quote numbers) |
| Xero | sales | XeroMarketThemeMapping, XeroMarketTaxMapping, XeroMarketAccountMapping, XeroMarketTaxAccountMapping, XeroUsStateMapping, XeroIntegrationSettings |
| Notifications | gateway | NotificationOutbox, NotificationDelivery, NotificationEventSetting, Notification, UserNotificationPreference, AppAnnouncement |
| Manufacturing / MRP | mrp | MrpUserProfile, MrpSupplier*, MrpDocument, MrpLineItem, MrpMaterial, MrpMaterialCategory, MrpStock*, MrpManufacturingBatch, MrpBatchUnit*, MrpRecipeException*, MrpProductionBatch*, MrpInventoryCount, MrpWarehouse, MrpBoothModel, MrpBoothElement, MrpElementBomLine, MrpBomMissingMaterialCode, MrpElectricModule*, MrpElectricAssembly*, MrpRecipeVersion*, MrpCorrectionLog, MrpSyncAttempt, MrpSheetSyncLog, MrpOneShotScript (`mrp_one_shot_script`) |
| Factory floor & planning | factory | FactoryStation*, FactoryBoothModel, FactoryElement, FactoryColor, FactoryBoothOption, FactoryProduction*, FactoryStationWorkItem, FactoryStationIssue, FactoryPanelScrap*, FactorySetting, FactoryWorkSession, FactoryQuota, FactoryScheduleTaskOverride, FactoryDevice, FactoryCnc*, FactoryPlanning*, FactorySite, FactoryBoothVersionCode, FactoryBatchProductionOption, FactoryBoothProductionOption, FactoryWorker, FactoryStationAssignment, FactoryStationBreak, FactoryPallet, FactoryPalletLine, FactoryPalletHold, FactoryModelPanelEffort, FactoryPanelOrder, FactoryPanelOrderEvent, FactoryPanelOrderScrapReport |
| Clock-In | clock | ClockWorker, ClockCardBinding, ClockPendingUid, ClockUnassignedTap, ClockEvent, ClockWorkSettings, ClockDevice, ClockDeviceEvent, ClockExcludedDay (snake_case tables via `@@map`) |
| Spare parts / panels (RP) | rp | RpRequest, RpLineItem, RpInternalProductionRow, RpPhoto, RpSheetSyncOutbox, RpSheetRowMap, RpAddressBookEntry, RpPanelCatalogOption, RpExportTrackingRow, RpNumSequence, RpIpNumSequence, RpAutomationState, RpLifecycleEvent, RpPartMrpMap, RpPanelMrpMap, RpSparePart, RpPanelOption |
| Task management | tasks | TaskWorkspace, TaskWorkspaceMember, TaskBoardColumn, Task, TaskAssignee, TaskExternalLink, TaskComment, TaskAttachment, TaskIntegration, TaskUserSettings |
| Feature requests | requests | FeatureRequest, FeatureRequestVote, FeatureRequestAttachment |
| Partner stock | stock | StockPartner, StockPartnerVisit |
| Physical booth inventory | inventory | BoothFamily (booth catalogue, read by every app), ProductionBatch (batch master), InventoryAccess, InventoryWarehouse*, InventorySpot, InventoryPallet*, InventoryFactory, InventoryBatch, InventoryFinish, InventoryCatalogMapping, InventoryUnit, InventoryDemand*, InventorySuggestion, InventoryAllocation, InventoryExportLine, InventorySerialSequence, InventoryTransfer*, InventoryPreparationTask, InventoryAuditEvent, InventoryOperation, InventoryIntegrationEvent; also writes `BoothUnit.inventoryUnitId/serialCode/inventorySyncedAt` |
| Zeron material checker | zeron-material-checker | ZeronSheetState, ZeronImportRun, ZeronImportedTab, ZeronDeliveryRow, ZeronAcceptedUnitCost (the app keeps its own local schema; MRP reads `ZeronDeliveryRow`) |
| Dev backlog | dev | BacklogFamily, BacklogApp, BacklogItem, BacklogItemRelation, BacklogLink, BacklogComment, BacklogAttachment, BacklogSubscriber, BacklogActivity, BacklogOverviewPreference |

Other apps may **read** tables they don't own (e.g. gateway reads assembly
counts for tool-card stats) but should only **write** through the owner app.

The ten Factory floor tables that the Factory app used to create at runtime
(`FactoryWorker`, `FactoryStationAssignment`, `FactoryPallet`,
`FactoryPalletLine`, `FactoryPalletHold`, `FactoryModelPanelEffort`,
`FactoryStationBreak`, `FactoryPanelOrder`, `FactoryPanelOrderEvent`,
`FactoryPanelOrderScrapReport`) and its runtime columns are declared here since
0.101.0, exactly as production has them
([scripts/add-factory-floor-tables.sql](scripts/add-factory-floor-tables.sql)).

The MRP recipe-version tables (`MrpRecipeVersionScope`,
`MrpRecipeVersionAmendment`, `MrpRecipeVersionDocumentLink`) and
`mrp_one_shot_script`, with the MRP columns its build-time SQL added, are declared
here since 0.102.0, exactly as production has them
([scripts/add-mrp-recipe-version-tables.sql](scripts/add-mrp-recipe-version-tables.sql)).
`MrpElectricAssemblyVersion` and `MrpRecipeVersionElectric.assemblyVersionId`
reach production with the same release
([scripts/add-mrp-electric-assembly-versions.sql](scripts/add-mrp-electric-assembly-versions.sql)).

Since 0.103.0 every public table in the production database is declared here.
The last ones, which app repositories had created with their own scripts (5 November
2026 audit, see [docs/database-audit-2026-11.md](docs/database-audit-2026-11.md)),
are the Tasks tables `TaskAttachment`, `TaskIntegration` and `TaskUserSettings` and
the Zeron material checker's five `Zeron*` tables and two enums, declared exactly as
production has them
([scripts/align-production-drift-2026-11.sql](scripts/align-production-drift-2026-11.sql)).
The Zeron app still keeps its own Prisma schema, which re-declares `User`,
`Account`, `ToolCard` and `ToolCardAccess` as a read-only subset and is never
pushed. The `neon_auth` schema belongs to Neon Auth, not to a MEAVO app.

Inventory uses the shared `BoothProductFamily` and `BoothUnitStatus` enums. Its
physical `InventoryUnit` identities are independent of Sales `BoothUnit` demand
and regenerated Factory production rows. Sales and Factory may enqueue their
own `InventoryIntegrationEvent` rows transactionally; Inventory processes them
and owns all other inventory writes. See [Inventory V1](docs/inventory-v1.md) for
the schema contract and required SQL-only allocation/expiry constraints.

Inventory also owns three shared masters that every app reads (cross-app data
review, release 1; [docs/data-model.md](docs/data-model.md) § Booth catalogue,
batch master and booth identity): `BoothFamily`, one row per booth family keyed
by the serial prefix (`SO WS C2 C4 H1 HF H2 H4`); `ProductionBatch`, one row per
batch code with `FactorySite` as the site master; and `InventoryUnit` as the
single physical booth, whose `serialNumber` is the planning sheet's 5-digit booth
id. Factory, MRP and Sales rows point at them through nullable link columns;
Factory and MRP write their own links, and Inventory alone writes
`BoothUnit.inventoryUnitId`.

## SQL-only objects

Some of what the database holds cannot be written in `prisma/schema.prisma`, so
`prisma migrate diff` never reports it: CHECK constraints, partial and expression
indexes, triggers and their functions, and sequences. Scripts create them, and
[prisma/sql-only-objects.json](prisma/sql-only-objects.json) lists every one with the
definition PostgreSQL prints (98 at 0.112.0: 76 CHECK constraints, 7 partial indexes,
1 expression index, 8 triggers, 4 functions, 2 sequences). CI fails when a script adds,
changes or drops one without the inventory changing in the same PR, and when an entry is
deleted while its object still exists. How to add one, what CI does and does not prove,
and the read-only comparison with production are in
[docs/data-model.md](docs/data-model.md) § SQL-only objects.

The quote counter is one of them. `"SalesQuoteNumberSeq"` is the sequence Sales takes
every new quote number from (`MQ-00001`, ...; `nextval` in meavo-sales
`src/lib/quote-number.ts`). meavo-db owns it since 0.112.0:
[scripts/sales-quote-number-sequence.sql](scripts/sales-quote-number-sequence.sql)
creates it where it is missing and never touches one that exists. Never reset or restart
it; `Deal.quoteNumber` is unique.

## Documentation

| Doc | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Quick orientation for AI coding agents |
| [.cursor/rules/](.cursor/rules/) | Always-on Cursor rules |
| [docs/data-model.md](docs/data-model.md) | Domains, ownership, migration safety |
| [docs/architecture.md](docs/architecture.md) | Consumption model and release flow |
| [CONTRIBUTING.md](CONTRIBUTING.md) | PR and release process |

### Sales manual historical forecasts

Sales owns `SalesForecastManualRun`; it retains manual historical forecasts and per-run cost history alongside daily `SalesForecastRun` snapshots. Apply `scripts/sales-forecast-manual-runs.sql` before the consumer release.

Sales Marketing form reporting uses the additive `scripts/sales-marketing.sql` migration. It stores form metadata, submission identifiers/timestamps and resumable sync state, without contact fields. Apply to isolated staging before the Sales consumer; production migration and package publication go out with the approved release.
