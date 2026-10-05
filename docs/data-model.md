# Data model — meavo-db

The canonical schema lives **in this repo**: `prisma/schema.prisma` (~125 models, ~54 enums). This is the only repo allowed to alter the shared MEAVO Neon Postgres database; every app repo consumes it read-only via the `@meavo/db` git dependency and runs `prisma generate` only.

Pinned version: apps pin a git tag, e.g. `"@meavo/db": "git+https://github.com/meavo-booths/meavo-db.git#v0.13.0"` — current version in `package.json`.

## Domains (schema sections)

The schema is organized by owning app with `// ---- <Domain> (owner: <app>) ----` comments. Owners write their tables; other apps may read but write only through the owner app.

| Schema section | Owner app | Representative models |
|----------------|-----------|-----------------------|
| Identity & access | gateway | `User`, `Account`, `Team`, `TeamSubgroup`, `TeamMember`, `GatewayUserImportReceipt`, `ToolCard`, `ToolCardAccess`, `LoginThrottle` |
| HR & documents | gateway | `Employee`, `EmployeeSalaryHistory`, `DocumentTemplate*`, `GeneratedDocument`, `LibraryAsset`, `GatewaySheetRecord` |
| Vacation tracking | hols | `VacationRequest`, `UserAllowance`, `PublicHoliday` |
| Assembly | assembly | `Assembly`, `AssemblyPartner`, `Questionnaire*`, `QuestionnaireSubmission`, `Resource*`, `SheetImportState` |
| Sales | sales | `Product`, `ProductFamilyInfo`, `Client`, `ClientLabel`, `ClientLabelAssignment`, `ClientEvent`, `ClientEventReceipt`, `Deal`, `DealLabel`, `DealLabelAssignment`, `QuoteLineItem`, `BoothUnit`, `QuotePdfTemplate`, `QuotePdfMarketDefault` |
| Sales daily priorities | sales | `SalesRepIdentity`, `SalesPrioritySettings`, `SalesPriorityRun`, `SalesPriorityWorkItem`, `SalesOpportunitySnapshot`, `SalesCrmSnapshot`, `SalesCompanyResearch`, `SalesPriorityRecommendation`, `SalesPriorityFeedback` |
| Xero integration | sales | `XeroMarketThemeMapping`, `XeroMarketTaxMapping`, `XeroMarketAccountMapping`, `XeroIntegrationSettings` |
| Notifications | gateway | `NotificationOutbox`, `NotificationDelivery`, `NotificationEventSetting` |
| Manufacturing / MRP | mrp | `MrpDocument`, `MrpLineItem`, `MrpMaterial`, `MrpManufacturingBatch`, `MrpElementBomLine`, ... |
| Factory floor + planning | factory | `FactoryStation*`, `FactoryProduction*`, `FactoryPlanning*`, `FactoryDevice`, `FactoryCnc*` |
| RP spare parts / panels | rp | `RpRequest`, `RpLineItem`, `RpInternalProductionRow`, `RpSheetSyncOutbox`, `RpLifecycleEvent`, ... |
| Clock-In | clock | clock-in / time-tracking models (see `scripts/add-clock-tables.sql`) |
| Task management | tasks | `TaskWorkspace`, `TaskBoardColumn`, `Task`, `TaskAssignee`, `TaskExternalLink` |
| Feature requests | requests | `FeatureRequest`, `FeatureRequestVote`, `FeatureRequestAttachment` (`FeatureRequestType`, `FeatureRequestImportance`) |

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

There is **no Prisma migrations directory**. Follow [RELEASE_POLICY.md](../RELEASE_POLICY.md): test schema changes on an isolated non-production database and review them through `staging` before requesting approval for the exact production SQL and revision. The commands below are not permission to write to the shared production DB:

1. Edit `prisma/schema.prisma`; `npm run validate`.
2. `npm run diff` — **read the generated SQL**. Anything with `DROP` needs to be understood before going further; a stale or trimmed schema will drop other apps' tables.
3. Additive changes: `npm run db:push`.
4. Destructive or ordering-sensitive changes: write an **idempotent** script in `scripts/` (wrap `CREATE TYPE` etc. in `DO $$ ... EXCEPTION WHEN duplicate_object THEN NULL`), with an `-- Apply:` header, and run `npx prisma db execute --file scripts/<file>.sql --schema prisma/schema.prisma`. See `scripts/add-task-tables.sql` for the pattern.
5. Commit the version/schema changes on `feat/*` and open a PR against `staging`. Production application, `main` promotion, and release-tag/package publication require specific human approval. After the approved package release, prepare dependency bumps through each consumer’s feature-to-staging workflow.

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
approved package pins until a separately approved canonical package release;
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

## Sync / external copies

Several domains mirror rows to Google Sheets or queue side effects; the outbox/state tables live here, the sync code lives in the owning app:

- `NotificationOutbox` / `NotificationDelivery` — satellites enqueue, gateway sends email.
- `RpSheetSyncOutbox`, `RpSheetRowMap`, `SheetImportState`, `GatewaySheetRecord` — sheet sync state for rp / assembly / gateway.

## Queries agents should reuse

N/A — this repo contains no query code. Prisma client helpers, seeds, and repositories live in the consuming apps.

## Sales month-end forecasts

`SalesForecastSettings` is a singleton, Super Admin-only model selection and processing toggle independent from daily priorities. It defaults to paused and GPT-6 Sol.

`SalesForecastRun` retains one daily dated revenue forecast, its input snapshot, selected model/pricing and calculation/prompt versions. Expiring leases and bounded attempts allow safe cron recovery. Numerical inputs/results publish before optional AI briefing; known usage is accumulated and interrupted billing is flagged as incomplete. The model selects validated fact IDs and cannot change revenue estimates.

The run stores historical Deal and rep references inside JSON; no live User/Deal relationship can cascade-delete its history. Settings editor IDs are historical scalars, matching priority settings. No automatic retention deletion is introduced.

Apply `scripts/sales-month-end-forecast.sql` before the Sales staging deployment. The script only adds the two tables, checks and indexes. Existing generated Prisma clients remain compatible; the first Sales consumer uses parameterized SQL. Production application requires approval of the reviewed SQL/revision. Rollback retains historical tables and disables processing. No tag is required for the backwards-compatible SQL consumer.


## Opportunity forecast pilot (Sales)

`scripts/sales-opportunity-forecast.sql` adds an independently paused opportunity-processing flag to `SalesForecastSettings`, retaining the existing model selector. `SalesOpportunityForecastRun` freezes the model/configuration, known quoted pipeline, baseline and observed outcomes. `SalesOpportunityForecastItem` provides fenced per-family leases, prepared evidence, qualitative assessments and token/cost accounting. No trained conversion probabilities are stored in this pilot.

`SalesOpportunityQualification` stores the current rep-confirmed buyer facts; immutable `SalesOpportunityQualificationEvent` revisions preserve actor names/IDs and source notes. Historical deal/actor IDs have no live-user/deal foreign keys, so account deletion, reassignment and closure cannot erase prediction evidence. Run/item references use RESTRICT and there is no automatic retention deletion. Complete-opportunity collection starts 2026-08-15; imported historical wins are never treated as a conversion denominator.

Migration is additive and compatible with the pinned Sales Prisma client through bound SQL. Validate and apply in isolated staging before the Sales staging release. Production SQL, main release and processing activation require specific human approval. Rollback pauses processing and retains all tables.

## Manual historical forecast runs (Sales)

`SalesForecastManualRun` preserves independently requested historical forecasts and their AI usage. It shares the daily run's checkpoint/lease/accounting fields, adds a two-hour deadline and scalar requester attribution, and permits multiple runs per date. It has no User/Deal foreign keys or automatic deletion. Keeping manual executions separate preserves compatibility with the existing unique-per-day `SalesForecastRun` writers. Apply the additive `scripts/sales-forecast-manual-runs.sql` before the Sales settings release; rollback retains all data. The SQL consumer requires no new package tag. Production migration and both main releases require the reviewed-staging approval.

## Sales payment history

`SalesPayment` stores individual Xero, OA and manual net customer receipts with
separate received and recorded dates. Manual opening balances may be undated
until reconciled. Unique Xero IDs prevent duplicate imports; voided rows remain
for audit. Nullable Deal links use SET NULL to retain financial history.
`SalesPaymentWindow` tracks complete imported ranges; `SalesPaymentSync` leases
imports and records availability. Apply `scripts/sales-payment-history.sql`.

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
