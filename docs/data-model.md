# Data model — meavo-db

The canonical schema lives **in this repo**: `prisma/schema.prisma` (255 models, 103 enums at v0.103.0; 243 and 99 at v0.101.0; 231 and 97 at v0.100.0, whose per-table inventory with production row counts is [audit/tables-2026-11.csv](audit/tables-2026-11.csv)). This is the only repo allowed to alter the shared MEAVO Neon Postgres database; every app repo consumes it read-only via the `@meavo/db` git dependency and runs `prisma generate` only.

Pinned version: apps pin a git tag, e.g. `"@meavo/db": "git+https://github.com/meavo-booths/meavo-db.git#v0.13.0"` — current version in `package.json`.

## Domains (schema sections)

The schema is organized by owning app with `// ---- <Domain> (owner: <app>) ----` comments. Owners write their tables; other apps may read but write only through the owner app.

| Schema section | Owner app | Representative models |
|----------------|-----------|-----------------------|
| Identity & access | gateway | `User`, `Account`, `Team`, `TeamSubgroup`, `TeamMember`, `GatewayUserImportReceipt`, `ToolCard`, `ToolCardAccess`, `LoginThrottle` |
| HR & documents | gateway | `Employee`, `EmployeeSalaryHistory`, `EmployeeCommission`, `DocumentTemplate*`, `GeneratedDocument`, `SignatureRequest`, `LibraryAsset`, `LibraryVideo`, `UsefulLink`, `GatewaySheetRecord` |
| Vacation tracking | hols | `VacationRequest`, `UserAllowance`, `PublicHoliday` |
| Assembly | assembly | `Assembly`, `AssemblyPartner` (incl. `phone`), `Questionnaire*`, `QuestionnaireSubmission` (incl. `notes`), `Resource*`, `SheetImportState` |
| Sales | sales | `Product`, `ProductFamilyInfo`, `Client`, `ClientLabel`, `ClientLabelAssignment`, `ClientEvent`, `ClientEventReceipt`, `ClientMergeAudit`, `Deal`, `DealLabel`, `DealLabelAssignment`, `QuoteLineItem`, `BoothUnit`, `QuotePdfTemplate`, `QuotePdfMarketDefault` |
| Sales payments | sales | `SalesPayment`, `SalesPaymentWindow`, `SalesPaymentSync` |
| HubSpot integration | sales | `HubSpotMarketingSync`, `HubSpotMarketingForm`, `HubSpotMarketingSubmission`, `HubSpotLostReason`, `HubSpotDealSnapshot`, `HubSpotCampaignSyncState` |
| Sales daily priorities | sales | `SalesRepIdentity`, `SalesPrioritySettings`, `SalesPriorityRun`, `SalesPriorityWorkItem`, `SalesOpportunitySnapshot`, `SalesCrmSnapshot`, `SalesCompanyResearch`, `SalesPriorityRecommendation`, `SalesPriorityFeedback` |
| Sales forecasts | sales | `SalesForecastSettings`, `SalesForecastRun`, `SalesForecastManualRun`, `SalesOpportunityForecastRun`, `SalesOpportunityForecastItem`, `SalesOpportunityQualification`, `SalesOpportunityQualificationEvent` |
| Xero integration | sales | `XeroMarketThemeMapping`, `XeroMarketTaxMapping`, `XeroMarketAccountMapping`, `XeroMarketTaxAccountMapping`, `XeroUsStateMapping`, `XeroIntegrationSettings` |
| Notifications | gateway | `NotificationOutbox`, `NotificationDelivery`, `NotificationEventSetting`, `Notification`, `UserNotificationPreference`, `AppAnnouncement` |
| Manufacturing / MRP | mrp | `MrpDocument`, `MrpLineItem`, `MrpMaterial`, `MrpManufacturingBatch`, `MrpBatchUnit*`, `MrpElementBomLine`, `MrpRecipeVersion*`, `MrpElectric*`, `MrpStock*`, `MrpSheetSyncLog`, ... |
| Factory floor + planning | factory | `FactoryStation*`, `FactoryProduction*`, `FactoryPlanning*`, `FactoryDevice`, `FactoryCnc*`, `FactoryWorker`, `FactoryPallet*`, `FactoryModelPanelEffort`, `FactoryPanelOrder*` (the last four groups were runtime DDL in the Factory app until [add-factory-floor-tables.sql](../scripts/add-factory-floor-tables.sql)) |
| RP spare parts / panels | rp | `RpRequest`, `RpLineItem`, `RpInternalProductionRow`, `RpSheetSyncOutbox`, `RpLifecycleEvent`, ... |
| Clock-In | clock | clock-in / time-tracking models (see `scripts/add-clock-tables.sql`) |
| Task management | tasks | `TaskWorkspace`, `TaskBoardColumn`, `Task`, `TaskAssignee`, `TaskExternalLink`, `TaskComment`, `TaskAttachment`, `TaskIntegration`, `TaskUserSettings` |
| Feature requests | requests | `FeatureRequest`, `FeatureRequestVote`, `FeatureRequestAttachment` (`FeatureRequestType`, `FeatureRequestImportance`) |
| Partner stock | stock | `StockPartner`, `StockPartnerVisit` (stock quantities stay in the Ops Google Sheet) |
| Physical booth inventory | inventory | `BoothFamily` and `ProductionBatch` (shared masters, see below), `InventoryUnit`, `InventoryWarehouse*`, `InventoryPallet*`, `InventoryDemand*`, `InventoryAllocation`, `InventoryExportLine`, `InventoryTransfer*`, `InventoryIntegrationEvent`; also the only writer of `BoothUnit.inventoryUnitId/serialCode/inventorySyncedAt` (full contract in [inventory-v1.md](inventory-v1.md)) |
| Zeron material checker | zeron-material-checker | `ZeronSheetState`, `ZeronImportRun`, `ZeronImportedTab`, `ZeronDeliveryRow`, `ZeronAcceptedUnitCost` (the app keeps its own local schema and never pushes it; MRP reads `ZeronDeliveryRow` with raw SQL) |

The full authoritative matrix is in [README.md](../README.md) § Table ownership.

## Entity relationship (identity spine)

```
User ──< TeamMember >── Team
 │ ──< Account                      (OAuth)
 │ ──< ToolCardAccess >── ToolCard  (per-app access gating, kind APP_ACCESS)
 │ ──< VacationRequest / Deal / Task / Mrp* / Rp* ...   (domain FKs from every app)
```

All satellite domains foreign-key to the shared `User` / `Team` — never duplicate identity tables.
Historical Sales priority recipient/actor IDs are the deliberate exception:
their dated records survive account deletion and do not represent live access.
Known departures recorded by the 5 November 2026 audit ([database-audit-2026-11.md](database-audit-2026-11.md)):
`ClockWorker.userId` is optional, `AssemblyTeamMember` has no `User` link,
`AssemblyPartner` and `StockPartner` carry their own credentials, and
`Deal.createdByUserId`, `DealAuditLog.actorUserId`, `RpRequest.userId` (which
holds an e-mail address) and the Factory `crewWorkerId*` columns are scalar ids
without a relation.

### Team subgroups and user imports

`TeamSubgroup` is an optional organizational label inside one existing team.
Its name is unique within that team; another team may reuse the same name.
`TeamMember.subgroupId` is nullable and its composite foreign key with `teamId`
guarantees the subgroup belongs to the membership's team. Existing memberships
stay unassigned. Subgroups do not grant tool access, change team roles or holiday
allowances, or create a separate approval boundary. Gateway may rename a subgroup
but does not reparent it. An assigned subgroup cannot be deleted; move or clear
its memberships first. A team change must clear or replace the old subgroup.

`GatewayUserImportReceipt` records a successful Gateway import in the same
transaction as its writes. Its client-generated request ID, acting user and
request hash let Gateway return the original result after a lost response,
without repeating salary entries, resetting generated passwords or enqueueing
notifications twice. The JSON result contains only safe row statuses and counts;
never store uploaded CSV contents, payroll values or plaintext credentials.
Gateway must verify the acting user and request hash before returning a receipt.

Apply `scripts/add-team-subgroups.sql` after reviewing the schema diff and
verifying the environment. It is additive, transactional and safe to rerun.
Older consumers can keep reading teams and memberships without selecting the
new nullable column. Older code that replaces a membership drops its subgroup,
so Gateway must preserve or explicitly clear subgroup assignments when changing
teams. Roll back application code without dropping these tables or the column;
keep imported user/HR data and receipts intact. Any production SQL or package
publication requires separate approval under `RELEASE_POLICY.md`.

### Tool-scoped access roles

`ToolCardAccess.role` uses `ToolAccessRole` (`MEMBER`, `ADMIN`) and defaults to
`MEMBER`. Adding the column does not promote anyone, including existing
company-wide admins. Gateway exposes and edits this role for Sales only, from
both user access and tool access management. Other tools retain their existing
membership behavior. Removing membership removes its role; regranting without an
explicit role creates a `MEMBER`. Gateway must preserve roles on retained rows
when editing unrelated access.

`User.systemRole = ADMIN` remains the existing company-wide **Super Admin**.
A Sales tool `ADMIN` is not a Super Admin: Sales grants only won-deal line editing
and team generated-priority history review. AI configuration, usage/costs and
permission management remain Super Admin-only. The apps enforce capabilities
server-side and require current Sales membership even for Super Admins; this
enum alone does not authorize a request.

## Naming & style

- PascalCase models, camelCase fields, `cuid()` string IDs, `SCREAMING_SNAKE` enum values.
- Domains ported from legacy systems (RP, some MRP/Factory tables) keep their original snake_case table names via `@@map` / `@map` — keep that mapping intact when editing them.
- New models go inside their owner's `// ---- ... ----` section; a new app gets a new section at the end plus a row in README's ownership table.
- New satellite apps also need: a `ToolCard` seed in gateway (kind `APP_ACCESS`, stable `seed-<app>-tool` ID) and notification event types in gateway's event catalog — those live in the gateway repo, not here.

## Applying changes (migration safety)

There is **no Prisma migrations directory**. Follow [RELEASE_POLICY.md](../RELEASE_POLICY.md): test schema changes on an isolated non-production database and review them through `staging` before the release that carries it to production. The commands below are not permission to write to the shared production DB:

1. Edit `prisma/schema.prisma`; `npm run validate`.
2. `npm run diff` — **read the generated SQL**. Anything with `DROP` needs to be understood before going further; a stale or trimmed schema will drop other apps' tables.
3. Additive changes: `npm run db:push`.
4. Destructive or ordering-sensitive changes: write an **idempotent** script in `scripts/` (wrap `CREATE TYPE` etc. in `DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL`), with an `-- Apply:` header, and run `npx prisma db execute --file scripts/<file>.sql --schema prisma/schema.prisma`. See `scripts/add-task-tables.sql` for the pattern, and `scripts/add-booth-identity-links.sql` for guarded foreign keys (`IF NOT EXISTS (SELECT 1 FROM pg_constraint ...)`) and NULL-only backfills.
   CI runs `scripts/verify-sql-replay.sh`: the diff from the base branch must be additive, apart from whole statements in its `REVIEWED` list (each one names the script that performs it and why it cannot lose data), and the scripts listed in it, each applied twice to a database built from the base schema, must produce `prisma/schema.prisma` exactly. Add a new script to that list in the same PR.
5. Commit the version/schema changes on `feat/*` and open a PR against `staging`. The release yes (staging → `main`) covers `main` promotion, the release tag and production application (`scripts/apply-sql.sh production`). After the approved package release, prepare dependency bumps through each consumer’s feature-to-staging workflow.

Consumer apps must **never** run `db:push` themselves — their partial schemas would drop everyone else's tables.

## Sales deal collections and labels

`DealLabel.kind` separates `STANDARD` labels from `CAMPAIGN` labels while sharing
the existing assignment table. Apply `scripts/sales-label-campaigns.sql` before
the updated Sales consumer. Existing rows and older writers default to
`STANDARD`; label IDs, assignments, normalization and global name uniqueness
remain unchanged. The reserved `OA Invoice` label is constrained to `STANDARD`.
Campaigns are internal reporting/filter metadata and do not appear on feed cards
or customer documents. New quote variations inherit editable label assignments;
subsequent edits are independent.

Validate the SQL twice against an isolated database. Package/tag publication,
production SQL, and Sales deployment require the separate release approvals in
`RELEASE_POLICY.md`. Old consumers can still read and write their known columns,
but would present campaigns as ordinary labels; create campaign data only after
the updated Sales consumer is deployed. Rollback retains the additive column,
enum and assignments; do not delete campaign data or drop the enum/column.

`Deal.amountCollected` is the cash collected so far on a won deal, in the
invoice currency and excluding VAT (the same basis as the Ops File's "Amount
Collected" column). The Sales app sets it from the Xero payment sync and from
manual payment edits; null means it has not been recorded yet.

`DealLabel` / `DealLabelAssignment` mirror the client label tables: a reusable
catalogue with a case-insensitive unique `normalizedName` (SQL check keeps it
equal to `lower(btrim(name))`) and a composite-key assignment per deal.

## Sales client profiles

`Client.notes` stores shared plain-text notes, initially empty. Custom labels use
the reusable `ClientLabel` catalogue and `ClientLabelAssignment` composite key;
the Sales app trims names and stores the lower-case value in `normalizedName`.
Its unique index prevents duplicate labels regardless of case. Notes, label
assignments, and events are per client and never inherited across the hierarchy.

`ClientEvent` records date-only activity, attribution, and an optional
`Decimal(12,2)` expense with EUR, GBP, USD, or CZK currency. SQL checks require a
nonnegative amount paired with a supported currency, or both fields absent.
Creator/editor names remain as historical attribution when a shared `User` is
deleted; nullable user links use `SET NULL`.

`ClientEventReceipt` reserves a unique server-generated `storageKey` before an
upload and tracks `PENDING`, `READY`, and `DELETE_PENDING` states. The Sales app
validates uploaded metadata before exposing a receipt, and retries failed file
cleanup without dropping its storage key. Soft-deleted events remain until every
receipt has been removed; `RESTRICT` foreign keys block premature event/client
deletion. Only non-deleted events contribute to visible timelines and expense
totals. Cleanup and app authorization are implemented by Sales.

Apply `scripts/client-profile-activity.sql` for this change, including on an
environment already updated with `db push`: Prisma does not express the expense
and normalized-name CHECK constraints. The script is additive, transactional,
and idempotent. Review the live schema diff before applying, then follow the
tagged release and consumer-bump process above.

## Sales client merges

`Client.mergedIntoClientId` is a permanent alias to the retained client. Merged
rows keep their old identity and scalar values for old links, but become
immutable. A later merge can create an alias chain; resolve it in Sales rather
than rewriting earlier aliases. Nullable `mergedByUserId` links the shared user,
and `mergedAt` records retirement. The source has no parent after retirement.

`ClientMergeAudit.id` is the server-created preview UUID and transaction
idempotency key. A unique `sourceClientId` allows one committed merge per source.
The JSON snapshots, explicit resolutions, and transferred record IDs preserve
what was approved; those JSON references intentionally have no foreign keys to
deals or events that may later be cleaned up. Audit updates/deletes and merged
client updates/deletes are rejected. Shared User deletion can only null its
attribution foreign keys. Client deletion is restricted by aliases and audits.

`Deal.xeroRoutingMode` defaults to `FOLLOW_CLIENT`, preserving existing behavior.
`FIXED` requires both the original contact ID and connection key. `UNMATCHED`
preserves the absence of an accounting match without a fallback. Both
`FOLLOW_CLIENT` and `UNMATCHED` require null routing identifiers. Sales captures
the effective routing before moving deals; the database does not call Xero or
change quote/invoice snapshots.

Apply `scripts/client-merge.sql` before the new Sales consumer. It adds columns,
an enum, audit storage, checks, and triggers without rewriting existing rows.
The source is retired last: every deal, contact, label assignment, child client,
and event (including soft-deleted events awaiting receipt cleanup) must already
be moved or removed. Receipt keys and event IDs stay unchanged. The triggers
reject insertion or reassignment to an already merged client; updates that leave
the client ID unchanged continue to work for historical deals and cleanup.

For merge transactions, Sales acquires sorted per-deal advisory locks in
namespace `1819242082`, then sorted profile-contact advisory locks in namespace
`1819242086`, then the client creation/name advisory lock in namespace
`1819242085`, then all affected Client row locks in sorted ID order, then
Deal/Event row locks. Profile-contact operations hold their advisory lock across
external work and local linking, so a merge cannot retire their client between
those steps. Attachment guards use `FOR SHARE` on the target Client
to serialize their active check with retirement. Writers that change an
attachment must follow the same order; triggers protect data integrity but do
not eliminate deadlocks from older writers with a different lock order. Treat a
deadlock or serialization failure as a failed transaction and retry/re-preview
through the application. Receipt cleanup needs only its existing Event lock.

Run `scripts/client-merge-check.sql` only on an isolated database: it creates
transactional fixtures and rolls them back. Validate the migration twice before
the checks; an in-memory PGlite database initialized with the prior Prisma schema
is sufficient for constraint/trigger checks. Real concurrent sessions are still
needed to verify blocking/lock ordering. Follow the release policy for schema,
package, and consumer rollout. Older consumers may write active clients, but
merges must remain disabled until every relevant Sales read/write path supports
aliases. Rollback keeps the additive schema and guards: never remove aliases or
audit evidence to roll an application back.

## Sales daily priorities

`SalesRepIdentity` maps a unique canonical rep name and optional unique HubSpot
owner ID to the existing shared `User`. Mappings default to active and can be
disabled; recommendation ownership must not be inferred from the quote creator.

`SalesPrioritySettings` holds the singleton AI model selection (`id = default`).
The app treats an absent row as the default `gpt-6-sol` profile and creates the
row on its first settings save. `modelProfile` is a validated app catalog key,
not a database enum; the app owns supported model/reasoning/pricing profiles.
`updatedById` retains historical editor attribution without a live User foreign
key. Settings reads and writes require Sales access and the existing company-wide
Super Admin role; the tool-scoped Sales Admin role does not grant AI administration.

`SalesPriorityRun` stores one unique business `runDate`, the input `cutoffAt`,
publication `deadlineAt`, model and prompt version, lifecycle status, and
completion time. The Sales app owns the business timezone and status transitions.
Nullable `modelConfig` freezes the selected model, reasoning and pricing profile
when a run starts. Its contents belong to that run; later settings edits must not
change an in-progress or completed run. The worker resumes using that saved
configuration. Legacy rows remain null and retain the old model/low-reasoning
interpretation; the migration does not rewrite their history. The app enforces
snapshot immutability and the overnight scheduling policy.
`SalesPriorityWorkItem` is a durable queue with a unique `(runId, kind, key)`,
attempt count, retry availability, and a lease token/expiry. `input` and `result`
are versioned JSON payloads; the result may include token usage and cost. Queue
claiming, lease fencing, retry limits, and kind/status validation belong to Sales.

`SalesOpportunitySnapshot` preserves the input evidence captured for one quote
family in a run, including its representative deal and optional recipient. Its
native `familyId`, `dealId`, and `userId` are scalar historical references, not
foreign keys. This preserves the features when a source deal or user is deleted.
Sales starts with the native capture, then saves the exact enriched model input
atomically with a lease-accepted deal assessment; snapshots are immutable after
that finalization. The same scalar policy applies to work-item attribution and
recommendation family/deal references.

`SalesCrmSnapshot` caches the latest enriched payload per HubSpot deal.
`SalesCompanyResearch` caches company facts per normalized website domain, with
fetch/expiry timestamps. Facts must retain source URLs and retrieval evidence;
Sales validates their content and only uses research fresh enough for the run.
These mutable caches do not replace the immutable opportunity snapshots.

`SalesPriorityRecommendation` stores each recipient's ranked daily suggestions
and structured, grounded content. A family occurs at most once per run/recipient;
Sales persists the ranked candidates and displays the first three that remain
eligible, so a closed or dismissed quote can be replaced by the next candidate.
`SalesPriorityFeedback` records `HELPFUL`, `DISMISSED`, or `ACTED` idempotently per
recommendation/recipient/kind; Sales enforces that the authenticated recipient
owns the recommendation. Kinds and statuses remain strings so future app changes
can introduce values without changing a shared Postgres enum.
Each feedback row may carry a nullable free-text `comment` (for example why a
suggestion was dismissed). Sales trims and caps it, and a repeated submission of
the same kind may fill or replace the comment without creating another row.
Comments are rep-authored and untrusted: quote them as data if they are ever
fed back into recommendation prompts.

Recommendations and feedback retain `userId` as a scalar historical identity,
with a nullable frozen `userName`. They have no User foreign key. New Sales
writes save the display name independently of live account relationships,
including `userName` in REP work-item input so empty/failed result groups retain
their recipient label. Existing records are backfilled from the current account
name/email, then saved matching opportunity/work inputs where available. A name
that cannot be recovered remains unknown; history already removed by an earlier
cascade cannot be reconstructed by this migration.

Deleting a run cascades to its work, feature snapshots, recommendations, and
their feedback. Deleting a User still cascades to live identity mappings and
tool access, but preserves priority recommendations, feedback, opportunity
snapshots and work-item attribution. There is no automatic deletion policy.
History shows the original generated ranks/content/feedback, independently of
dismissal, ownership/value changes or deal deletion; it does not prove the rep
viewed a suggestion. Live status belongs in a separate current-state display.

Apply `scripts/sales-daily-priorities.sql` only after reviewing the additive schema
diff and verifying the database target. It creates eight tables, their indexes,
and foreign keys transactionally and is idempotent. No existing columns or data
are changed, so older Sales releases remain compatible. Validate on an isolated
non-production database before production approval, applying the script twice to
check rerun safety. Rollback is to disable the new worker/UI and leave these
additive tables in place; do not drop history as part of an application rollback.
Schema application, a consumed package release, and consumer rollout each follow
the release-policy approval steps above.

Apply `scripts/sales-admin-priorities.sql` after the daily-priorities script and
before Gateway/Sales role and history releases. It adds the tool role and nullable
names, removes only the two destructive User-to-history foreign keys, and
backfills missing names without overwriting frozen labels on reruns. The earlier
daily-priorities script no longer recreates those foreign keys. Verify the schema
diff (one enum, three columns, two foreign-key removals), apply twice on an
isolated database, and test account deletion before staging application. Existing
row IDs, indexes, uniqueness rules and run/recommendation relationships remain.

Older consumers can omit the new fields: memberships default to `MEMBER` and
names remain nullable. Consumers may use parameterized SQL with their existing
approved package pins until the next approved release;
do not publish a production tag merely to test staging. Rollback means reverting
app behavior while retaining schema/history. An older Gateway's delete/recreate
access save may reset retained roles to `MEMBER`; avoid those saves until the
role-preserving version is restored. Never restore cascading history foreign
keys or delete historical rows as an application rollback.

Apply `scripts/sales-priority-settings.sql` before the Sales model-selector
release. It creates the settings table and adds only a nullable `modelConfig`
column to existing runs. The SQL-only `SalesPrioritySettings_singleton_check`
must be applied even if Prisma already created the table. Existing insert paths
remain compatible, and applying the script again preserves the selected profile
and all saved run configurations. Settings SQL writers must supply `updatedAt`;
Prisma manages that timestamp via `@updatedAt`. Roll back app behavior without
dropping the settings table or run history. Staging verification does not require
publishing a package tag, and production migration/tag/app releases each follow
the release-policy approval steps above.

Apply `scripts/sales-priority-feedback-comment.sql` before the Sales release that
writes feedback comments. It adds only the nullable `comment` column to
`SalesPriorityFeedback`; existing rows and older Sales releases (which name their
insert columns) are unaffected, and rerunning it is a no-op. Roll back app
behavior without dropping the column or saved comments.

Apply `scripts/sales-payments-override.sql` before the Gateway and Sales
releases that read or write the Payments right. It adds
`ToolCardAccess.paymentsOverride` (NOT NULL, default false, so no existing grant
gains the right) and the nullable `Deal.xeroInvoiceRemovedAt` /
`Deal.xeroFinalInvoiceRemovedAt`. The Payments right is Sales-only and
independent of the Sales role: a holder may override a won deal's payment status
and collected amount even when it is synced from Xero; Super Admins have it
implicitly. Gateway grants it; Sales enforces it server-side. The removed-at
columns are written by the Sales Xero payment sync when Xero reports an invoice
DELETED or VOIDED, and cleared when Sales unlinks that invoice so a replacement
can be created. Rerunning the script is a no-op. Roll back app behavior without
dropping the columns or granted rights.

## Sync / external copies

Several domains mirror rows to Google Sheets or queue side effects; the outbox/state tables live here, the sync code lives in the owning app:

- `NotificationOutbox` / `NotificationDelivery` — satellites enqueue, gateway sends email.
- `RpSheetSyncOutbox`, `RpSheetRowMap`, `SheetImportState`, `GatewaySheetRecord` — sheet sync state for rp / assembly / gateway.
- `InventoryIntegrationEvent` — Sales/Factory transactional producer queue; Inventory consumes idempotently and owns stock/allocations. No physical booth FK points at recreatable Factory units or cascading Sales demand; the links run the other way (Factory, MRP and Sales rows point at `InventoryUnit` with `ON DELETE SET NULL`).

## Inventory V1

The Inventory domain is additive and reuses the gateway `User` and Sales family/
status/payment enums. Apply its scripts in this order through the normal
environment review process, each twice: [add-inventory-v1.sql](../scripts/add-inventory-v1.sql),
[add-inventory-unit-cost.sql](../scripts/add-inventory-unit-cost.sql),
[add-inventory-v2-allocation-rules.sql](../scripts/add-inventory-v2-allocation-rules.sql),
[add-inventory-export-lines.sql](../scripts/add-inventory-export-lines.sql),
[add-booth-unit-inventory-link.sql](../scripts/add-booth-unit-inventory-link.sql).
This is required even after `db push`: the active-allocation partial indexes,
hold expiry limits, pending-allocation rule, package receipt checks and serial
bounds are not expressible in the Prisma schema.

The [domain contract](inventory-v1.md) documents data ownership, transactions,
integration identities, source-version reconciliation, migration and rollback.

## Booth catalogue, batch master and booth identity

Release 1 of the [cross-app data review](cross-app-data-review-2026-11.md)
(section 6) joins the parallel copies of booth models, batches and physical
booths without changing any app workflow. Everything is additive; every link
column is nullable and every backfill fills NULLs only. Apply the four scripts
in this order, each twice: [add-booth-family-catalog.sql](../scripts/add-booth-family-catalog.sql),
[add-production-batch-master.sql](../scripts/add-production-batch-master.sql),
[add-booth-identity-links.sql](../scripts/add-booth-identity-links.sql),
[add-factory-floor-tables.sql](../scripts/add-factory-floor-tables.sql).

**Booth catalogue.** `BoothFamily` (owner: inventory, read by every app) has one
row per `BoothProductFamily`, keyed by the two-letter serial prefix:

| code | family | name | factoryCode | mrpName | line |
| --- | --- | --- | --- | --- | --- |
| SO | SOHO | Soho | SO | Soho | Classic |
| WS | WORKSTATION | Workstation | SW | Workstation | Classic |
| C2 | CAMDEN_2 | Camden 2 | C2 | Camden 2 | Classic |
| C4 | CAMDEN_4 | Camden 4 | C4 | Camden 4 | Classic |
| H1 | HAVEN_ONE | Haven One | H1 | Haven One | Haven |
| HF | HAVEN_FOCUS | Haven Focus | HF | Haven Focus | Haven |
| H2 | HAVEN_2 | Haven Two | H2 | Haven Two | Haven |
| H4 | HAVEN_4 | Haven Four | H4 | Haven Four | Haven |

`BoothProductFamily` stays the key in the Sales and Inventory columns that use
it; `BoothFamily.family` is unique, so those columns join the catalogue without
migrating. `FactoryBoothModel.familyCode` and `MrpBoothModel.familyCode` are
unique nullable FKs to `BoothFamily.code`, backfilled by `factoryCode` and by
`lower(name)` = `mrpName`, `name` or one of the lower-case `aliases`
("camden 7", "meavo two", "h.f", …); MRP's "Custom Batch" stays unlinked.
`nameBg` is the label the Factory floor shows today. `ResourceBoothModel.family`
copies Assembly's `boothModel` into the shared enum; the `BoothModel` enum is
removed in release 3. Seed rows are insert-only, so names edited later survive a
rerun. Versions (`BoothFamilyVersion`) follow in release 2.

**Batch master.** `ProductionBatch` (owner: inventory) has one row per batch code
(`AB193`, `KB134`, `VB202`), its `FactorySite` (the site master for
`MrpWarehouse.siteId` and `InventoryFactory.siteId` too), optional family,
month, planned quantity and dates, US flag and a `ProductionBatchStatus`
(`PROPOSED`, `PLANNED`, `IN_PRODUCTION`, `PARTIALLY_READY`, `READY`,
`CANCELLED`). `FactoryPlanningBatch`, `FactoryProductionBatch`,
`MrpManufacturingBatch` and `InventoryBatch` each gain a unique nullable
`productionBatchId` (`ON DELETE SET NULL`). The backfill creates master rows from
planning batches first, then Factory production codes, then MRP names that are
plain codes, then Inventory batch numbers; satellite MRP rows such as
`AB-VB202/VB203` get no master row. The status is the most advanced state any
copy reports; `versionCode` stays null until release 2. `sourceSystem` is
`sheet` (with `sourceId` = the sheet row key `AKS:AB193`) or `inventory`. From
release 1 the Inventory worker keeps the master in step with Factory's
`plan.upsert` and `plan.status` events; from release 2 the Inventory app
creates batches.

**Booth identity.** `InventoryUnit` is the single physical booth. Its
`serialNumber` equals the planning sheet's 5-digit booth id for every sheet-born
booth, and app-born booths continue that series. `InventoryUnit` gains
`productionBatchId` (`ON DELETE RESTRICT`) and `plannedSortOrder`. The other
copies point at it with unique nullable links (`ON DELETE SET NULL`):
`FactoryPlanningBooth.inventoryUnitId` (backfilled where
`serialNumber = boothUniqueId::int`), `FactoryProductionBoothUnit.inventoryUnitId`
(set by Factory's stable materialise step; no backfill),
`MrpBatchUnit.inventoryUnitId` (backfilled from the id in `boothIdText`, e.g.
`SO 11704 AB146`; rows that hold `TRUE` stay null) and
`BoothUnit.inventoryUnitId`, which becomes a real foreign key. Inventory never
points at the Factory, MRP or Sales copies.

**Factory floor tables.** The ten tables and nine columns that the Factory app
created at runtime are declared here as production has them, including the
SQL-only indexes `FactoryPalletLine_combo_key` and
`FactoryStationBreak_station_open_key`.

**Names and rules kept as production has them.** Two objects are declared the way
production and staging already have them (0.102.1): the unique index on
`MrpElementBomLine` (`recipeVersionId, boothElementId, colour, market, materialId`)
is mapped to its PostgreSQL-truncated name `…_colour_market_`, and
`SalesOpportunityForecastItem.runId` uses `ON UPDATE NO ACTION` (run ids are never
updated). [align-forecast-fk-and-bom-index-names.sql](../scripts/align-forecast-fk-and-bom-index-names.sql)
brings databases built from older schemas to the same state and changes nothing on
production or staging. Neither change alters the generated Prisma client's field
names: `map:` sets only the database name.

**Production drift declared (0.103.0).** The 6 November 2026 comparison of the
production catalog with the schema found objects production had and the schema
did not. They are now declared as production has them, and
[align-production-drift-2026-11.sql](../scripts/align-production-drift-2026-11.sql)
creates them in databases built from older schemas (it changes nothing on
production):

- `DEFAULT CURRENT_TIMESTAMP` on 14 `updatedAt` columns (`@default(now()) @updatedAt`)
  and empty-array defaults on `Assembly.issueCategories` and `Questionnaire.eventTypes`.
- `Deal.xeroFinalSyncedAt` and `Deal.xeroPaymentSyncedAt` are `timestamptz`
  (`@db.Timestamptz`); `mrp_one_shot_script.ran_at` has no explicit precision.
- `Assembly.issueCategory`, the legacy single category that `issueCategories`
  replaced (dropped in 0.104.0, see below).
- The Tasks tables `TaskAttachment`, `TaskIntegration` and `TaskUserSettings`, and
  the Zeron material checker's tables and enums (own section at the end of the
  schema). `TaskIntegration.userId`, `TaskUserSettings.userId` and
  `ZeronAcceptedUnitCost.deliveryRowId` have no foreign key in production and none
  is declared.

What the schema still cannot express stays in SQL only and is left as production
has it: 73 CHECK constraints, 7 partial or expression unique indexes, 6 unique
constraints that Prisma models as unique indexes, `NOT NULL` on five scalar-list
columns, and the value order of three enums (`FeatureRequestType`,
`InventoryAllocationKind`, `PaymentTerms`), which is not changed because it sets
dropdown order.

**Legacy issue category dropped (0.104.0).** `Assembly.issueCategory` held one
category per assembly until the Assembly app moved to `issueCategories` in July
2026; nothing has read or written it since. On the owner's decision
[drop-assembly-issue-category.sql](../scripts/drop-assembly-issue-category.sql)
drops it, after its 483 production values were exported for the record.
[align-production-drift-2026-11.sql](../scripts/align-production-drift-2026-11.sql)
no longer re-adds it.

**Serial sequence range (0.104.0).** `InventorySerialSequence.nextNumber` may hold
10000 to 100000 (100000 = series exhausted) instead of 40000 to 100000, so the row
can record the real next booth number of the one five-digit series
([relax-inventory-serial-sequence-check.sql](../scripts/relax-inventory-serial-sequence-check.sql));
its default is 10000.

**Factory schedule task overrides.** `FactoryScheduleTaskOverride` is keyed by
`(batchId, elementId, processStep, assignedStationId)`: one panel job can sit on
several ASM stations at once, each with its own `sortOrder`, while progress stays
shared through the production events. Production has had this key since the
Factory app widened it; [widen-factory-task-override-pk.sql](../scripts/widen-factory-task-override-pk.sql)
(0.102.0) brings staging and fresh databases to the same key and changes nothing
where `assignedStationId` is already in the primary key. The Prisma compound
unique input is `batchId_elementId_processStep_assignedStationId`.

**MRP recipe versions and electric kits.** The recipe-version metadata
(`MrpRecipeVersion.kind`, colours, flags, `introducedOn`, `lockedAt`), the
`MrpRecipeVersionScope`, `MrpRecipeVersionAmendment` and
`MrpRecipeVersionDocumentLink` tables, `MrpManufacturingBatch.prefix/sequence`,
`MrpBatchUnit.electricDeductionPosted`, `MrpElectricModule.boothModelId`, the
`electric_consumption` movement type and the `mrp_one_shot_script` marker table
were created by MRP's own build-time SQL; since 0.102.0 they are declared here as
production has them (`scripts/add-mrp-recipe-version-tables.sql`).
`MrpElectricAssemblyVersion` and `MrpRecipeVersionElectric.assemblyVersionId`,
declared since 0.78.0 but never applied to production, are created there by
`scripts/add-mrp-electric-assembly-versions.sql` (empty table, nullable column).

## Queries agents should reuse

N/A — this repo contains no query code. Prisma client helpers, seeds, and repositories live in the consuming apps.

## Sales month-end forecasts

`SalesForecastSettings` is a singleton, Super Admin-only model selection and processing toggle independent from daily priorities. It defaults to paused and GPT-6 Sol.

`SalesForecastRun` retains one daily dated revenue forecast, its input snapshot, selected model/pricing and calculation/prompt versions. Expiring leases and bounded attempts allow safe cron recovery. Numerical inputs/results publish before optional AI briefing; known usage is accumulated and interrupted billing is flagged as incomplete. The model selects validated fact IDs and cannot change revenue estimates.

The run stores historical Deal and rep references inside JSON; no live User/Deal relationship can cascade-delete its history. Settings editor IDs are historical scalars, matching priority settings. No automatic retention deletion is introduced.

Apply `scripts/sales-month-end-forecast.sql` before the Sales staging deployment. The script only adds the two tables, checks and indexes. Existing generated Prisma clients remain compatible; the first Sales consumer uses parameterized SQL. Production application goes out with the approved meavo-db release. Rollback retains historical tables and disables processing. No tag is required for the backwards-compatible SQL consumer.


## Opportunity forecast pilot (Sales)

`scripts/sales-opportunity-forecast.sql` adds an independently paused opportunity-processing flag to `SalesForecastSettings`, retaining the existing model selector. `SalesOpportunityForecastRun` freezes the model/configuration, known quoted pipeline, baseline and observed outcomes. `SalesOpportunityForecastItem` provides fenced per-family leases, prepared evidence, qualitative assessments and token/cost accounting. No trained conversion probabilities are stored in this pilot.

`SalesOpportunityQualification` stores the current rep-confirmed buyer facts; immutable `SalesOpportunityQualificationEvent` revisions preserve actor names/IDs and source notes. Historical deal/actor IDs have no live-user/deal foreign keys, so account deletion, reassignment and closure cannot erase prediction evidence. Run/item references use RESTRICT and there is no automatic retention deletion. Complete-opportunity collection starts 2026-08-15; imported historical wins are never treated as a conversion denominator.

Migration is additive and compatible with the pinned Sales Prisma client through bound SQL. Validate and apply in isolated staging before the Sales staging release. Production SQL and the main release go out with one release yes; processing activation needs its own yes. Rollback pauses processing and retains all tables.

## Manual historical forecast runs (Sales)

`SalesForecastManualRun` preserves independently requested historical forecasts and their AI usage. It shares the daily run's checkpoint/lease/accounting fields, adds a two-hour deadline and scalar requester attribution, and permits multiple runs per date. It has no User/Deal foreign keys or automatic deletion. Keeping manual executions separate preserves compatibility with the existing unique-per-day `SalesForecastRun` writers. Apply the additive `scripts/sales-forecast-manual-runs.sql` before the Sales settings release; rollback retains all data. The SQL consumer requires no new package tag. Production migration and both main releases require the reviewed-staging approval.

## Sales payment history

`SalesPayment` stores individual Xero, OA and manual net customer receipts with
separate received and recorded dates. Manual opening balances may be undated
until reconciled. Unique Xero IDs prevent duplicate imports; voided rows remain
for audit. Nullable Deal links use SET NULL to retain financial history.
`SalesPaymentWindow` tracks complete imported ranges; `SalesPaymentSync` leases
imports and records availability. Apply `scripts/sales-payment-history.sql`.

## Sales Discount RRP (0.105.0)

`Product.discountRrp` is a nullable third catalog price (in the product's
`currency`) used on Retail deals only; null means the product has none.
`QuoteLineItem.discountRrpApplied` marks a line whose FIXED discount was set from
it, so Sales can recompute the discount on a currency change and clear it on a
switch to Trade. The line keeps `unitPrice` at the Retail price; totals, PDF and
Xero read the existing discount fields. Apply `scripts/sales-discount-rrp.sql`
(two additive columns; older clients ignore both).

## Assembly "Delivery Only" event type

`AssemblyEventType` gains `DELIVERY_ONLY` for visits where MEAVO only delivers the
booth (no install). Apply `scripts/add-assembly-delivery-only-event-type.sql`; it is
one idempotent `ALTER TYPE ... ADD VALUE IF NOT EXISTS`, so no rows, columns or other
enum values change.

Compatibility: **not** safe for older clients once a row holds the new value. Prisma
throws when it reads an enum value missing from its generated client. Consumers of
`Assembly.eventType`: Assembly (writes it) and Sales (`deals/[id]` page selects it).
Tasks selects only `id`/`dealId` and Gateway does not read assemblies. So the order is:
publish the tag, release Sales on it, apply the SQL to production, and only then release
Assembly. Sales goes first so no client that cannot read the value exists when a row can
first hold it. The SQL goes before Assembly because Assembly offers the option to staff as
soon as it is released; releasing it earlier would show an option that fails with an
invalid-enum database error until the SQL is applied. Applying the SQL before Assembly
is safe: no app offers the value yet. Anything that can save an assembly against the
shared database, including a staging deployment, counts as offering it.
Validate on an isolated non-production database first, applying the script twice.

Rollback: Postgres cannot drop an enum value, so the value stays. Stop offering it in
Assembly's dropdown and re-type any `DELIVERY_ONLY` rows (for example to `ASSEMBLY`).
Schema application, the package tag, and each consumer release follow the
release-policy approval steps above.
It adds three tables and indexes without modifying existing data. The consumer
uses parameterized SQL with its existing generated client, as forecast stores
do, so no dependency tag publication is required for this additive release.

## Assembly questionnaire section text

`QuestionnaireSection.description` and `QuestionnaireSectionTranslation.description` are
nullable text columns holding the partner-facing sentence under an image-upload step's
title (e.g. "Attach photos of the repair"). Null means Assembly shows its built-in default
copy, so existing sections are unchanged. Apply
`scripts/questionnaire-section-description.sql` (two idempotent
`ADD COLUMN IF NOT EXISTS`, no backfill).

Compatibility: apply the SQL before releasing any consumer on a client that includes these
fields. Prisma selects every scalar column of a model by default, so a client that knows
the columns fails on a database without them. Only Assembly reads these models.

## Assembly visit scope

`Assembly.visitBooths` and `Assembly.visitContacts` are nullable jsonb columns for a
follow-up visit (repair, aftercare, moving service, info). They record the booths and
site people for that job, copied from the linked sale as a starting point and then
edited on the assembly. Null means the assembly still shows the sale. The sales deal
is not updated. Apply `scripts/assembly-visit-scope.sql` (two idempotent
`ADD COLUMN IF NOT EXISTS`, no backfill) before a consumer that selects the columns.
Rollback is `DROP COLUMN` of both; existing rows lose only the visit override.
