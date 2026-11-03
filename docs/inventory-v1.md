# Inventory V1 schema contract

Inventory (`inventory.meavo.app`) owns the physical stock register. The canonical
schema remains here in `meavo-db`; consumers only generate Prisma clients.
Schema and SQL are additive. Apart from three nullable link columns on Sales
`BoothUnit` that only Inventory writes (see "BoothUnit write-back"), they do not
modify Sales, Factory production models, MRP recipes, gateway identity, existing
stock, or serials.

## Ownership and identities

| Area | Models and contract |
| --- | --- |
| Access | `InventoryAccess` grants one or more VIEWER, SALES, OPS_PRODUCT, WAREHOUSE, FACTORY or ADMIN roles to existing gateway `User` records. Gateway's APP_ACCESS card is a separate required entry gate, seeded in gateway. |
| Warehouses | `InventoryWarehouse` is LOCAL or CENTRAL; `InventoryWarehouseServiceRule` matches country, optional region and postcode prefix and records priority/lead time. A deal's preferred warehouse is an override of ranking, not electrical eligibility. |
| Physical placement | Optional `InventorySpot`, named `InventoryPallet`, and `InventoryPalletContent` support mixed pallets and booths split over several pallets. A package has a durable `(unitId, packageKey)` identity. Composite FKs keep a pallet's spot in its actual warehouse. |
| Production origin | `InventoryFactory` and `InventoryBatch` retain factory and manually entered batch number. The batch/factory composite FK prevents a booth claiming the wrong factory. Source keys link upstream records without destructive cascades. |
| Compatibility | `BoothProductFamily` and `BoothUnitStatus` reuse Sales' canonical enums. `InventoryFinish` represents an exact reviewed finish, including custom specifications. `InventoryCatalogMapping` links source model/finish IDs and recipe revisions explicitly; with `sourceKind="market"` it maps a Sales `Deal.market` value to a delivery `countryCode` so automatic allocation can pick a warehouse. Multi-country markets stay unmapped. |
| Physical booth | `InventoryUnit` exists before serial assignment or a customer. Production/transit/receipt update this same record. Factory source keys must be permanent handover keys, never regenerated panel/production-unit IDs. |
| Commercial demand | `InventoryDemand` mirrors a stable quote/deal identity and source version; `InventoryDemandLine` stores quantity and compatibility. Slot `1..quantity` identifies each requested booth. Neither has a cascading FK to Sales. Retire removed lines with `active=false`. The demand also mirrors the deal's `paymentStatus`, `paymentTerms`, `deliveryType` and `deliveryAddress` at the last sync and stores Inventory's computed `paymentCleared` gate; `shipDirect` is set in Inventory and never overwritten by sync. |
| Advisory matching | `InventorySuggestion` stores demand version, proposed unit versions, explanations/preparation, and shortages as a JSON snapshot. Saving a suggestion never locks stock, allocates a booth, or issues a serial. |
| Allocations | `InventoryAllocation` connects one booth to one demand-line slot. Only ACTIVE rows consume stock; SQL guarantees one ACTIVE row per booth and per demand-line slot. `kind` is QUOTE_HOLD (explicit rep request), DEAL_HOLD (automatic, won but unpaid, expires within seven days) or COMMITTED (paid, no expiry). `origin` AUTOMATIC rows are pending while `confirmedAt` is null; MANUAL rows are confirmed at creation (SQL check). Every confirmed change is audited. |
| Export lines | `InventoryExportLine` is one row per allocation on the weekly export list: typed export week, workshop note, spare parts, labels-printed and loaded timestamps, and the frozen destination (serving warehouse or direct delivery address). A composite FK to `(allocationId, unitId)` keeps the line on its allocation's booth. The pallet number is `InventoryPalletContent`, not a column here. |
| Sales booth unit link | `BoothUnit.inventoryUnitId` (unique), `serialCode` and `inventorySyncedAt` are written only by Inventory when an allocation links a physical booth to that Sales demand row; Sales shows them read-only. No FK, so Sales works without the Inventory tables. |
| Serials | `InventorySerialSequence` has one `global` row whose `nextNumber` starts at 40000. Unit serial number and full serial are independently unique. Legacy prefixes/numbers are retained; new Workstation serials use WS. |
| Transfers | `InventoryTransfer` manifests and `InventoryTransferItem` receipt quantities distinguish dispatch from partial/complete receipt. A transfer item targets a complete unpackaged booth or an exact package, never both. |
| Preparation | `InventoryPreparationTask` records socket fitting/checking/picking. Composite FK ensures the task's allocation belongs to the same physical unit. Completed preparation stays with that booth. |
| History/retries | `InventoryAuditEvent` stores before/after, reason, shared User actor and name snapshot; `InventoryOperation` stores a request hash and atomic result for replay. |
| Integration queue | `InventoryIntegrationEvent` is a durable producer queue keyed by `(sourceSystem, sourceEventId)`. Sales and Factory may enqueue in their existing DB transaction; only Inventory consumes and mutates stock. |

`socketType` is a configured, normalized code; `null` means no installed socket
on physical stock or an unresolved requirement on demand. Voltage is UNKNOWN,
V110_120 or V220_240 and is independent from socket. UNKNOWN voltage, unresolved
finish/socket requirements, and unreviewed catalog mappings are not safe matches.
Local supply must have the right installed socket. Central supply may be socket
agnostic but still needs the right voltage and a fitting task before shipment.

`InventoryUnit.warehouseId` is an actual location summary, not a promised
destination. `intendedWarehouseId` is used for future stock. A package-level move
must update this summary only after checking every package: receiving one pallet
does not move or complete all booths represented on it. Clear the summary when
the unit spans locations; the package/pallet records explain where the parts are.

## Booth inventory cost

`InventoryUnit.costAmount` is the recorded inventory cost of that physical booth,
stored as `Decimal(12,2)`. It is not the Sales quote price. `costCurrency` is its
uppercase, three-letter ISO 4217 currency code. Both values are nullable and must
be recorded or cleared together. A missing cost means **unrecorded**, whereas a
recorded zero is valid and must remain distinguishable from missing information.
There is no default cost or automatic valuation from a model, quote, or recipe.

Apply `scripts/add-inventory-unit-cost.sql` after the base Inventory V1 script,
including when Prisma has already added the columns. This separate, additive,
transactional script leaves existing rows unvalued and can be replayed safely.
SQL checks require paired fields, a nonnegative amount excluding numeric `NaN`,
and an uppercase three-letter currency shape. The Inventory application must
validate the selected currency against supported ISO 4217 codes and audit cost
changes. Keep totals separated by currency unless an explicit exchange-rate
policy is implemented; do not silently add amounts from different currencies.

Review a schema-to-schema SQL diff, apply the script twice to an isolated local
database, and exercise null, zero, positive, invalid currency, negative and
unpaired values before rollout. Old consumers can ignore these nullable fields.
Rollback keeps the columns and recorded amounts intact while reverting consumer
code. Production application and package release require the same approval as the
rest of the Inventory schema.

## Automatic allocation and product confirmation

Winning a deal no longer merely suggests stock. The Inventory worker reserves
specific booths for a WON demand automatically, using the same matching rules as
suggestions, and those rows are real allocations that consume stock: `kind`
DEAL_HOLD with a seven-day `expiresAt` while the deal is not paid, or COMMITTED
with `expiresAt=null` once `paymentCleared` is true (`paymentStatus` PAID or
PARTIALLY_PAID, or NET_* terms). They are created with `origin=AUTOMATIC` and
`confirmedAt=null`, which means **pending Ops/Product confirmation**, and carry
no serial. Confirmation (or an override swap) by Ops/Product sets `confirmedAt`
and issues the serial; Sales users cannot confirm, swap or release won-deal
allocations. A live quote hold is converted in place on win (keeping its
original expiry until payment clears). An expired DEAL_HOLD is released; when
payment later arrives the worker reserves again from whatever is available.
Suggestions remain advisory snapshots and still hold nothing.

Apply `scripts/add-inventory-v2-allocation-rules.sql` after the base and cost
scripts. It adds the enum value and origin column, makes `confirmedAt` nullable,
swaps the hold-expiry check for one that covers DEAL_HOLD, adds the demand
payment/delivery columns and the mapping `countryCode`. Existing rows keep their
`confirmedAt` and become MANUAL, so nothing becomes pending retroactively.

## Export lines

`scripts/add-inventory-export-lines.sql` adds `InventoryExportLine`, the weekly
loading list that replaces the Ops sheet's export tab. Lines are created lazily
by the Inventory service when Ops type a value; `loadedAt` marks dispatch and
freezes the destination (a `WAREHOUSE` row names the serving warehouse and,
once dispatched, the transfer; a `DIRECT` row keeps the address label). SQL
checks require a destination on loaded rows, a warehouse on WAREHOUSE rows and
an ISO week shape such as `2026-W45`. Release or swap of an unloaded
allocation deletes its line in the same transaction; loaded lines are history.

## BoothUnit write-back

`scripts/add-booth-unit-inventory-link.sql` adds `inventoryUnitId` (unique),
`serialCode` and `inventorySyncedAt` to Sales `BoothUnit`. The Inventory
service writes them, together with `status` and `location`, whenever an
allocation or the allocated booth's status changes, in the same transaction.
It maps a demand-line slot to the n-th Sales booth unit of the same family and
finish, keeps an existing link in place, and clears stale links before setting
new ones so the unique index never fails during a swap. It never touches the
`Deal` row, so `Deal.updatedAt` and source versions stay stable. Rows without an
active allocation are reset to PLANNED with no link.

## Required transaction behavior

The schema supports these rules; the Inventory service must enforce the listed
cross-row/business rules inside serializable transactions with conflict retries.

1. Verify the caller's role, stable request key and payload hash. Replaying a
   committed `InventoryOperation` returns the saved result; reusing its key for a
   different action/payload is rejected. Record the result in the action's same
   transaction. In-progress duplicate requests must not perform a second action.
2. Reconcile source versions before demand writes. Older/repeated events cannot
   restore cancelled lines or undo a protected allocation. `sourceVersion` is a
   BigInt so an upstream `updatedAt` timestamp in epoch milliseconds fits; JSON
   boundaries must convert it to a safe number or decimal string. Quote variations
   share the same stable demand family and replace the active variation; they
   must not add duplicate holds for alternate quotes.
3. Suggestions are snapshots. Confirmation rechecks the demand/unit versions,
   source demand state, all compatibility rules, quantity/slot bounds, readiness,
   and current allocation. Reject stale suggestions without a silent substitute.
4. Expire past-due ACTIVE quote holds before a claim and availability calculation.
   Expiry depends on the current clock, so an SQL partial index cannot do this
   automatically. Lock/recheck expired rows in the same transaction as the claim
   to serialize expiry versus won-deal confirmation. Cleanup jobs are optional
   housekeeping, never the correctness boundary.
5. A quote hold requires an explicit rep request and human confirmation. SQL
   limits `expiresAt` of QUOTE_HOLD and DEAL_HOLD rows to at most seven days
   after `reservedAt`; both timestamps stay unchanged on quote saves or
   overrides. Winning converts a live quote hold in place: to DEAL_HOLD keeping
   its original expiry while unpaid, or to COMMITTED with `expiresAt=null` once
   payment clears. Refreshing suggestions converts nothing. An expired hold
   cannot be revived; a later payment reserves afresh.
11. Automatic allocation runs only for WON demands under a service actor that no
    HTTP caller can obtain. It rechecks the Sales revision, candidate units and
    specifications exactly like confirmation, creates `origin=AUTOMATIC` rows
    with `confirmedAt=null` and no serial, and is idempotent on replay. Only
    Ops/Product confirm (issuing the serial) or swap pending rows; Sales
    callers are refused on won-deal allocations.
6. Serialize number assignment with the global sequence row in the same
   allocation transaction. Lazily create it at 40000, skip numbers already
   imported, advance with an atomic update/row lock, and stop at 99999. SQL allows
   nextNumber=100000 only as the exhausted sentinel. Assign no serial from a
   suggestion or an ordinary quote save. Format new serials as `MODEL NUMBER
   BATCH`; number, prefix and full serial stay with the physical booth forever.
7. Ops/Product may override with a reason. Validate and claim the replacement
   before releasing the original, as one atomic transaction. Preserve quote
   expiry, protect the selection from ordinary Sales changes, audit the actor and
   reason, and cancel/update uncompleted preparation. Do not move physical stock
   when changing an allocation. Cross-deal moves need explicit review of both
   demands. Customer-dispatched stock requires the separate correction workflow.
8. Dispatch/receipt must validate manifest quantities against current package
   quantities/locations and outstanding transfers; lock those rows. Do not put
   the same package or complete booth on two active manifests. SQL prevents
   duplicate entries inside one manifest and over-receipt, while cross-manifest
   and complete-unit-versus-package exclusion are service responsibilities.
9. Factory handover upserts by permanent source identity. Replayed handovers do
   not create extra booths. Packed/checked sets acceptance on the existing unit;
   warehouse receipt establishes physical location. Completion of panel counters
   or a batch alone does not establish that every unit is ready.
10. Keep immutable identity, completed prep and history on release/cancellation.
    All mutations write an attributed audit event. Serial fields must not be
    erased, reassigned or edited through ordinary service operations.

The PostgreSQL constraints are a final conflict barrier, not authorization.
Callers must not write Inventory domain tables directly from browser clients.
Scalar historical actor/source IDs retain attribution if upstream objects are
deleted; the audit and confirming-user relations point at the existing User.

## Integration event envelope

Use `sourceSystem` (for example SALES or FACTORY), a stable producer-generated
`sourceEventId`, `action`, optional `actorUserId`, versioned `payload`, and optional
`payloadHash`. A duplicate source event cannot enqueue twice. The consumer updates
`status`, `attempts`, `lastError`, and `processedAt`. Failed events remain visible
and retryable. Protect processing against concurrent workers with a row lock or
atomic claim; complete domain effects and PROCESSED state in one transaction.

Sales commercial changes must not be rolled back merely because an optional
Inventory deployment is temporarily unavailable. Integrate by adding an event
in the same source transaction once this schema is installed and the feature is
enabled. Before the schema is installed, keep the integration feature disabled.
The producer queue is the sole exception to Inventory's write ownership.

## Application and rollout

Apply the Inventory scripts in order, each twice, through the repository release
policy, even if Prisma `db push` created the tables already:
`add-inventory-v1.sql`, `add-inventory-unit-cost.sql`,
`add-inventory-v2-allocation-rules.sql`, `add-inventory-export-lines.sql`,
`add-booth-unit-inventory-link.sql`. Prisma cannot express the partial
ACTIVE-allocation indexes, hold expiry limits, the pending-allocation rule,
serial bounds or quantity checks. Each script is a single transaction, uses
idempotent table/type/index/constraint creation, and contains no data seeds or
destructive DDL; the only existing-domain ALTERs are the nullable `BoothUnit`
link columns. They rely on existing `User`, `BoothProductFamily`,
`BoothUnitStatus`, `PaymentStatus`, `PaymentTerms` and `DeliveryType` objects.

Before application, inspect the actual target provider/project/database branch,
compare its schema with the reviewed canonical schema, and verify non-production
isolation. Validate the generated schema-to-schema SQL and run this script twice
on a disposable PostgreSQL database to prove replay safety. Then exercise the
allocation conflict, expiry, serial, package/transfer and FK constraints before
staging. Existing objects with a different shape are a migration-review error;
IF NOT EXISTS is not a substitute for reviewing drift.

The app deployment, gateway card/roles, shared schema, and enabled Sales/Factory
producer hooks must be coordinated. Import opening stock only after a reviewed
preview checks duplicate legacy serials (including the 40000 range), exact
finishes/electrical values, warehouses, source identities and active allocations.
Do not run uncontrolled spreadsheet and Inventory writes concurrently.

Rollback is additive: disable producer/consumer feature flags and leave these
tables/data intact. Do not drop stock, allocations or audit rows to revert app
code. A separate reviewed correction can reconcile any processed events. No
production SQL, package tag or deployment is authorized by this document.

Local consumers may generate against the unpublished schema path for validation.
The package version is intentionally unchanged until an approved release. Do not
publish a release tag simply to make a feature build resolve the new client.

## Local verification evidence

On 25 September 2026, Prisma validation passed with a dummy localhost URL, and
schema-to-schema SQL diff from baseline `e4cd715d58db37fe94746cf3f4cb147f9fbe9e1b`
contained only new Inventory objects. An isolated in-memory PGlite PostgreSQL
instance passed 40 assertions: installation of the full baseline, Inventory DDL
twice, both active-allocation unique indexes, hold/commit expiry rules, first
serial 40000 and uniqueness/range/exhaustion, batch/factory and spot/warehouse
consistency, mixed-package identities, partial receipts and over-receipt rejection,
manifest/route consistency, preparation/allocation ownership, idempotency keys,
retained actor history, and epoch-millisecond source version round-trip.

These checks exercised the SQL directly with synthetic fixtures. They do not
prove the Inventory service's authorization, concurrent transaction retry logic,
integration delivery, app flows, or any external/staging environment. Those
require consumer verification before rollout. No external database was accessed.

The subsequent booth-cost addition passed Prisma validation with an explicit
dummy loopback URL. A schema-to-schema diff against the preceding feature commit
contained only the two nullable `InventoryUnit` columns. A fresh, in-memory
PGlite database accepted the separate cost script twice, preserved a pre-existing
unit's null cost, accepted null/zero/positive/maximum values, allowed paired
clearing, and rejected 13 invalid amount/currency combinations including `NaN`,
infinities, overflow, negative, unpaired, lower-case and malformed values. These
isolated checks did not read or modify the running local preview or any external
database.

On 3 November 2026, after rebasing onto staging (`9e1979e`, 0.99.0), Prisma
validation passed and a schema-to-schema diff from the previous commit listed
exactly the objects in the three new scripts. A fresh in-memory PGlite database
built from staging's schema accepted all five Inventory scripts twice in order.
Behaviour checks: an automatic DEAL_HOLD pending for seven days and an automatic
pending COMMITTED row were accepted; a DEAL_HOLD expiring after eight days and a
MANUAL row without `confirmedAt` were rejected; an export line was accepted for
its allocation's booth and rejected for another booth, a malformed week, a
loaded row without destination and a WAREHOUSE row without warehouse, while a
loaded DIRECT row was accepted; a lower-case market country was rejected and
`GB` accepted. No external database was accessed.
