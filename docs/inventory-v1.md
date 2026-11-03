# Inventory V1 schema contract

Inventory (`inventory.meavo.app`) owns the physical stock register. The canonical
schema remains here in `meavo-db`; consumers only generate Prisma clients.
Schema and SQL are additive. They do not modify Sales `BoothUnit`, Factory
production models, MRP recipes, gateway identity, existing stock, or serials.

## Ownership and identities

| Area | Models and contract |
| --- | --- |
| Access | `InventoryAccess` grants one or more VIEWER, SALES, OPS_PRODUCT, WAREHOUSE, FACTORY or ADMIN roles to existing gateway `User` records. Gateway's APP_ACCESS card is a separate required entry gate, seeded in gateway. |
| Warehouses | `InventoryWarehouse` is LOCAL or CENTRAL; `InventoryWarehouseServiceRule` matches country, optional region and postcode prefix and records priority/lead time. A deal's preferred warehouse is an override of ranking, not electrical eligibility. |
| Physical placement | Optional `InventorySpot`, named `InventoryPallet`, and `InventoryPalletContent` support mixed pallets and booths split over several pallets. A package has a durable `(unitId, packageKey)` identity. Composite FKs keep a pallet's spot in its actual warehouse. |
| Production origin | `InventoryFactory` and `InventoryBatch` retain factory and manually entered batch number. The batch/factory composite FK prevents a booth claiming the wrong factory. Source keys link upstream records without destructive cascades. |
| Compatibility | `BoothProductFamily` and `BoothUnitStatus` reuse Sales' canonical enums. `InventoryFinish` represents an exact reviewed finish, including custom specifications. `InventoryCatalogMapping` links source model/finish IDs and recipe revisions explicitly. |
| Physical booth | `InventoryUnit` exists before serial assignment or a customer. Production/transit/receipt update this same record. Factory source keys must be permanent handover keys, never regenerated panel/production-unit IDs. |
| Commercial demand | `InventoryDemand` mirrors a stable quote/deal identity and source version; `InventoryDemandLine` stores quantity and compatibility. Slot `1..quantity` identifies each requested booth. Neither has a cascading FK to Sales. Retire removed lines with `active=false`. |
| Advisory matching | `InventorySuggestion` stores demand version, proposed unit versions, explanations/preparation, and shortages as a JSON snapshot. Saving a suggestion never locks stock, allocates a booth, or issues a serial. |
| Allocations | `InventoryAllocation` connects one booth to one demand-line slot. Only ACTIVE rows consume stock; SQL guarantees one ACTIVE row per booth and per demand-line slot. Every confirmed change is audited. |
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
   limits `expiresAt` to at most seven days after `reservedAt`; both timestamps
   stay unchanged on quote saves or overrides. Confirming a won deal explicitly
   converts a live hold into COMMITTED with `expiresAt=null`; merely winning or
   refreshing suggestions does not convert it. An expired hold cannot be revived.
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

Apply `scripts/add-inventory-v1.sql` through the repository release policy, even
if Prisma `db push` created the tables already. Prisma cannot express the partial
ACTIVE-allocation indexes, quote expiry limit, serial bounds or quantity checks.
The script is a single transaction, uses idempotent table/type/index/constraint
creation, and contains no data seeds, existing-domain ALTERs or destructive DDL.
It relies on existing `User`, `BoothProductFamily` and `BoothUnitStatus` objects.

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
