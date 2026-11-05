# MEAVO shared database audit (5 November 2026)

## Summary

- One Neon Postgres database (243 MB, PostgreSQL 17.11) serves twelve MEAVO apps. The canonical Prisma schema (`meavo-db` `origin/main` 427d5a6, tag v0.100.0) declares 231 models and 97 enums; production holds 252 public tables plus 9 `neon_auth` tables.
- 22 public tables exist in production but not in the canonical schema. They were created by Factory runtime DDL, MRP and Tasks repository scripts, and the Zeron app's own Prisma schema. One schema model, `MrpElectricAssemblyVersion`, has no production table.
- 62 public tables are empty: 20 of the 23 Inventory tables (released on 4 November), 15 MRP document-scanning and recipe-exception tables, 6 Factory option and scrap tables, 7 Sales research and qualification tables, and 14 others.
- `FactoryPlanningImportRun` holds 122,894 rows (25 MB) from 75 days of planner imports; it is the largest table by rows. Two Sales snapshot tables take 86 MB between them.
- The same business concepts are stored in parallel: booth models in 2 enums and 2 tables, batches in 5 tables, physical booths in 7 representations, colours in 4 vocabularies with 109 spellings on the planning side, sites in 4 tables. None of these copies is joined by a foreign key.
- Data quality follows the missing joins: 1,390 of 1,603 planning booths have no model code, 244 of 1,224 MRP booth rows carry the text `TRUE` instead of a booth id, and 21 of 28 "version codes" are free notes.
- 86 models carry 140 id-like scalar fields with no relation. Where they point at live rows the orphan counts are zero; where they point at e-mail addresses or sheet keys they cannot be joined at all.
- 96 % of deal contacts duplicate a client contact by e-mail; three attachment, audit and outbox patterns are each repeated in several tables.
- Safe work now: documentation, the `BoothModel` enum, foreign keys with backfill, site links, import-run retention. The consolidation of batches, booths, colours and models needs app changes and is scheduled in the cross-app review roadmap.
- Every number below comes from a saved query file under `audit/queries/`; the row counts are real `count(*)` values, the sizes are physical relation sizes.

## Method and caveats

| Step | Source | Notes |
|---|---|---|
| Schema pass | `schema-main-427d5a6.prisma`, parsed by `analyze.py` into `audit/tables-2026-11.csv` | Section and owner come from the nearest `// ---- … (owner: x) ----` header; the parser also catches two `///` doc comments as pseudo-headers, so the CSV section column is indicative |
| Production statistics | `_shared/tools/prod-read.mjs`, single read-only statements; the statements are kept in `audit/queries/<name>.sql` in this repository, the result files (`<name>.json`) and the derived `rowcounts.json`, `analysis.json` and `analyze.py` live in the workspace folder `meavo-inventory/output/cross-app-review-2026-11/` | Taken 5 November 2026, 21:26 to 21:40 UTC |
| Row counts | `audit/queries/rowcounts_a_l.json`, `audit/queries/rowcounts_m_z.json`, merged into `rowcounts.json` | Real `count(*)` per public table |
| Sizes | `audit/queries/tables_a_l.json`, `audit/queries/tables_m_z.json`, `audit/queries/db_size.json` | `pg_total_relation_size`, includes indexes and TOAST |
| Activity counters | the same `pg_stat_user_tables` files, `audit/queries/unused_indexes.json` | **Unreliable on Neon**: the statistics collector restarts with the compute, so `n_tup_ins`, `n_tup_upd`, `n_live_tup`, `last_autoanalyze` and `idx_scan` describe activity since the last restart only. `audit/queries/stats_reset.json` shows no explicit reset. Nothing in this audit relies on them except the index note, which says so |
| Tables outside the schema | `audit/tables-outside-schema-2026-11.csv`, origins traced in the Factory, MRP, Tasks and Zeron repositories | 31 rows: 22 public, 9 `neon_auth` |
| Code facts | The three code traces of 5 November 2026 (schema map, Factory and MRP, Sales/Assembly/Inventory) | File references are to `meavo-db` `origin/main` and the app checkouts named in the review |

The 200-row cap of the helper truncates two results: `audit/queries/unused_indexes.json` (exactly 200 rows, so there may be more) and the colour list (135 rows, complete). All other result sets are below the cap.

## 1. Table inventory

### 1.1 Schema models by owner

| Owner | Models | Header sections in `schema.prisma` | Production rows (sum of the owner's tables, `audit/tables-2026-11.csv`) |
|---|---|---|---|
| sales | 53 | Sales, Xero integration, HubSpot integration (plus the priority and forecast models filed under it), Opportunity forecast (filed under Partner stock) | 88,188 |
| mrp | 36 | Manufacturing / MRP | 30,109 |
| factory | 31 | Factory floor, Factory planning | 126,598 (122,894 of them import runs) |
| gateway | 28 | Identity & access, HR & documents, Notifications | 18,890 |
| inventory | 23 | Physical booth inventory | 4 |
| assembly | 19 | Assembly | 3,595 |
| rp | 17 | RP spare parts / panels | 4,098 |
| clock | 9 | Clock-In | 274 |
| tasks | 7 | Task management | 257 |
| hols | 3 | Vacation tracking | 709 |
| requests | 3 | Feature requests | 32 |
| stock | 2 | Partner stock | 50 |

Full detail per model: `audit/tables-2026-11.csv` (model, table, schema line, section, owner, primary key, foreign keys and targets, soft keys, unique constraints, indexes, in canonical schema, in production, production rows, bytes).

Models filed under the wrong header (schema lines from the schema map):

| Models | Filed under | Belong to |
|---|---|---|
| `SalesRepIdentity`, `SalesPrioritySettings`, `SalesPriorityRun`, `SalesPriorityWorkItem`, `SalesOpportunitySnapshot`, `SalesCrmSnapshot`, `SalesCompanyResearch`, `SalesPriorityRecommendation`, `SalesPriorityFeedback`, `SalesForecastSettings`, `SalesForecastRun`, `SalesForecastManualRun` (lines 2056 to 2275) | "HubSpot integration (owner: sales)" | Sales priorities and forecasting; only five models in that section are HubSpot sync |
| `SalesOpportunityForecastRun`, `SalesOpportunityForecastItem`, `SalesOpportunityQualification`, `SalesOpportunityQualificationEvent` (4681 to 4745) | "Partner stock (owner: stock)" | Sales; the inline comment at 4680 says `owner: sales` |
| `FactoryPanelScrapReport`, `FactorySetting`, `FactoryPanelScrapPhoto`, `FactoryStationIssue` (3763 to 3864) | "Factory planning" | Factory floor |

### 1.2 Schema versus production

| Check | Result | Evidence |
|---|---|---|
| Schema models | 231 (plus 97 enums) | `analysis.json` |
| Public tables in production | 252 | `audit/queries/schemas.json` |
| Tables in another schema | 9 in `neon_auth` (`account`, `invitation`, `jwks`, `member`, `organization`, `project_config`, `session`, `user`, `verification`), 270 KB | `audit/queries/tables_non_public.json` |
| Schema models with no production table | 1: `MrpElectricAssemblyVersion` (schema line 2923) | `analysis.json` |
| Production tables not in the schema | 22 public, listed in 2.1 | `audit/tables-outside-schema-2026-11.csv` |
| Database size | 243 MB total, 228 MB in user tables | `audit/queries/db_size.json` |

## 2. Findings

### 2.1 Tables outside the canonical schema

22 public tables are created by app repositories, not by `meavo-db`. The release policy routes every schema change through `meavo-db`; these tables bypass it. The `neon_auth` schema is Neon's own authentication feature and is not a MEAVO app.

| Table | Rows | Origin | Where the DDL lives |
|---|---|---|---|
| `FactoryWorker` | 26 | Factory runtime DDL | `apps/web/scripts/sql/factory-workers.sql`, `lib/workers/ensure-workers-schema.ts` |
| `FactoryStationAssignment` | 4 | Factory runtime DDL | same scripts |
| `FactoryPallet` | 999 | Factory runtime DDL | `apps/web/scripts/sql/factory-pallets.sql`, `lib/pallets/ensure-pallets-schema.ts` |
| `FactoryPalletHold` | 1 | Factory runtime DDL | same |
| `FactoryPalletLine` | 0 | Factory runtime DDL | same |
| `FactoryModelPanelEffort` | 64 | Factory runtime DDL | `lib/planning/ensure-model-panel-effort.ts` |
| `FactoryStationBreak` | 30 | Factory runtime DDL | `lib/breaks/ensure-breaks-schema.ts` |
| `FactoryPanelOrder` | 0 | Factory runtime DDL | `apps/web/scripts/sql/factory-panel-orders.sql`, `lib/panel-orders/ensure-panel-orders-schema.ts` (on Factory `origin/main`, not in the 4 November worktree) |
| `FactoryPanelOrderEvent` | 0 | Factory runtime DDL | same |
| `FactoryPanelOrderScrapReport` | 0 | Factory runtime DDL | same |
| `MrpRecipeVersionAmendment` | 1 | MRP repo scripts | `scripts/add-mrp-recipe-version-v2.sql`, run by build-time `.mjs` scripts |
| `MrpRecipeVersionDocumentLink` | 6 | MRP repo scripts | same |
| `MrpRecipeVersionScope` | 6 | MRP repo scripts | same |
| `mrp_one_shot_script` | 1 | MRP repo scripts | bookkeeping for `backfill-electric-snapshots.mjs` and `cleanup-recipe-versions.mjs` |
| `TaskAttachment` | 0 | Tasks repo scripts | `scripts/add-task-attachments.sql` |
| `TaskIntegration` | 0 | Tasks repo scripts | `scripts/bootstrap-db.mjs` |
| `TaskUserSettings` | 0 | Tasks repo scripts | `scripts/add-task-user-settings.sql` |
| `ZeronDeliveryRow` | 1,353 | Zeron app schema | `zeron-material-checker/prisma/schema.prisma` |
| `ZeronImportRun` | 1 | Zeron app schema | same |
| `ZeronImportedTab` | 1 | Zeron app schema | same |
| `ZeronSheetState` | 1 | Zeron app schema | same |
| `ZeronAcceptedUnitCost` | 0 | Zeron app schema | same |

Two consequences:

- Factory also adds columns at runtime to schema-owned tables (`FactoryStationElementRequirement.effortUnits`, `FactoryProductionBatch.pauseNote`, `FactoryProductionEvent.palletId`, `cycleStartedAt`, `cycleSeconds`, `cycleKind`, `source`, `crewWorkerId1`, `crewWorkerId2`). Production has these columns; the canonical schema does not.
- The Zeron app re-declares `User`, `Account`, `ToolCard` and `ToolCardAccess` in its own schema as a documented local subset ("Never db:push this schema"). MRP reads `ZeronDeliveryRow` with raw SQL. The table therefore has two readers and no canonical definition.

### 2.2 Schema model with no production table

`MrpElectricAssemblyVersion` is declared at schema line 2923 and referenced by `MrpRecipeVersionElectric`, but production has no such table. Either the MRP electric v2 script was never applied to production or the model was added to `meavo-db` without its script. Any consumer on v0.100.0 that queries it will fail at runtime.

### 2.3 Empty tables

62 of 252 public tables have zero rows (`rowcounts.json`).

| Owner | Count | Tables |
|---|---|---|
| inventory | 20 | `InventoryAllocation`, `InventoryBatch`, `InventoryCatalogMapping`, `InventoryDemand`, `InventoryDemandLine`, `InventoryExportLine`, `InventoryFactory`, `InventoryFinish`, `InventoryIntegrationEvent`, `InventoryOperation`, `InventoryPallet`, `InventoryPalletContent`, `InventoryPreparationTask`, `InventorySerialSequence`, `InventorySpot`, `InventorySuggestion`, `InventoryTransfer`, `InventoryTransferItem`, `InventoryUnit`, `InventoryWarehouseServiceRule` (new on 4 November; `InventoryWarehouse` 1, `InventoryAccess` 1, `InventoryAuditEvent` 2) |
| mrp | 15 | `MrpBomMissingMaterialCode`, `MrpCorrectionLog`, `MrpDocument`, `MrpInventoryCount`, `MrpLineItem`, `MrpProductionBatch`, `MrpProductionBatchLine`, `MrpRecipeException`, `MrpRecipeExceptionBatchLink`, `MrpRecipeExceptionLineChange`, `MrpRecipeExceptionScope`, `MrpRecipeVersionBatchLink`, `MrpSupplier`, `MrpSupplierExtractionProfile`, `MrpSyncAttempt` (document scanning, recipe exceptions, material production plans: features not in use) |
| sales | 7 | `ClientEvent`, `ClientEventReceipt`, `SalesCompanyResearch`, `SalesForecastManualRun`, `SalesOpportunityQualification`, `SalesOpportunityQualificationEvent`, `XeroMarketTaxAccountMapping` |
| factory | 6 | `FactoryBatchProductionOption`, `FactoryBoothProductionOption`, `FactoryCncDailySummary`, `FactoryPanelScrapPhoto`, `FactoryPanelScrapReport`, `FactoryProductionBoothUnitOption` |
| outside schema | 8 | `FactoryPalletLine`, `FactoryPanelOrder`, `FactoryPanelOrderEvent`, `FactoryPanelOrderScrapReport`, `TaskAttachment`, `TaskIntegration`, `TaskUserSettings`, `ZeronAcceptedUnitCost` |
| clock | 2 | `clock_device_events`, `clock_excluded_days` |
| assembly | 1 | `PartnerNotificationPreference` |
| gateway | 1 | `EmployeeCommission` |
| hols | 1 | `UserAllowance` |
| rp | 1 | `panel_catalog_options` |

Empty is not the same as unused: the Inventory tables are days old, and `ClockExcludedDay` or `UserAllowance` may simply have no data yet. The MRP document-scanning set (`MrpDocument`, `MrpLineItem`, `MrpSupplier`, `MrpSupplierExtractionProfile`, `MrpCorrectionLog`, `MrpSyncAttempt`) and the recipe-exception set are the candidates to confirm with the MRP owner before anything is removed.

### 2.4 Size and growth hot spots

| Table | Bytes | Rows | Note |
|---|---|---|---|
| `SalesOpportunitySnapshot` | 45.9 MB | 11,183 | largest table; 4 KB per row |
| `SalesPriorityWorkItem` | 40.5 MB | 7,400 | 5.5 KB per row, lease queue with payloads |
| `FactoryPlanningImportRun` | 25.2 MB | 122,894 | one row per planner import between 14 August and 28 October 2026 (`audit/queries/import_runs.json`): about 1,640 runs per day. 7,243 runs record errors, 7,242 of them "missing booth_unique_id" (`audit/queries/import_run_errors.json`). The planner's GET sync imports 12 months for 3 sites per call |
| `SalesOpportunityForecastItem` | 13.5 MB | 1,299 | 10 KB per row: either large JSON payloads or dead tuples; vacuum candidate |
| `SalesForecastRun` | 8.3 MB | 39 | 213 KB per row, large JSON results |
| `Deal` | 7.9 MB | 6,977 | |
| `GatewaySheetRecord` | 7.5 MB | 2,750 | |
| `DealAuditLog` | 7.3 MB | 9,137 | |
| `MrpStockMovement` | 5.2 MB | 10,722 | |
| `QuoteLineItem` | 4.8 MB | 12,316 | |
| `MrpSheetSyncLog` | 4.5 MB | 6,198 | one row per 15-minute sync |
| `MrpElementBomLine` | 3.2 MB | 1,297 | 2.5 KB per BOM line: bloat candidate |
| `BoothUnit` | 2.4 MB | 9,132 | all created in 2026 (`audit/queries/boothunit_by_year.json`), i.e. a backfill |

Three log tables grow without bound: `FactoryPlanningImportRun`, `MrpSheetSyncLog` and `NotificationDelivery` (9,306 rows). None has a retention rule in the schema or the docs.

### 2.5 Booth models and families

| Representation | Kind | Values in production | Evidence |
|---|---|---|---|
| `BoothProductFamily` enum (schema 1099) | enum used by Sales `Product.boothFamily`, Inventory `InventoryUnit.family`, `InventoryDemandLine.family`, `InventoryCatalogMapping.family` | 8 values | schema |
| `BoothModel` enum (932) | enum used only by Assembly `ResourceBoothModel` | the same 8 values | schema |
| `FactoryBoothModel` (3298) | table, `code` unique | 8 rows: C2, C4, H1, H2, H4, HF, SO, SW with `nameBg` "Camden 2", "Camden 4", "Haven One", "Haven Two", "Haven Four", "Haven Focus", "Soho", "Workstation" and credits 1 to 2.3 | `audit/queries/models_factory.json` |
| `MrpBoothModel` (2675) | table, `name` unique | 9 rows: the same 8 names plus "Custom Batch"; every name equals a Factory `nameBg` exactly | `audit/queries/models_mrp.json`, `audit/queries/mrp_vs_factory_model_names.json` |
| Sales `Product` (1134) | table | 737 products; 189 of kind BOOTH carry a family (19 to 26 per family, in up to seven languages); 24 BOOTH-kind products carry no family and include add-ons such as a webcam, a handling fee and an office chair | `audit/queries/models_sales.json` |
| Sales `ProductFamilyInfo` (1207) | table | 22 rows: 8 families ("Haven Two", "Haven Four", "Camden 2", "Camden 4") plus 14 add-on groups with a null family | `audit/queries/models_family_info.json` |
| Planning `FactoryPlanningBooth.modelCode` | string | 1,390 of 1,603 booths null; 113 SO, 40 SW, 30 C2, 30 C4; no H1/HF/H2/H4 at all | `audit/queries/planning_model_codes.json` |

The model is agreed on by name between MRP and Factory and on enum value between Sales and Inventory, but the two pairs never meet. The planning import loses the model for 87 % of booths, so `FactoryPlanningBatch.modelCode` (set only when all booths agree) is mostly empty and the production sync falls back to MRP packing rows.

### 2.6 Batches

| Table | Rows | Status distribution | Linked to |
|---|---|---|---|
| `FactoryPlanningBatch` | 94 | 90 proposed, 4 ready | site FK; no FK to the others |
| `FactoryProductionBatch` | 36 | 4 active, 32 done | model FK; all 36 codes also exist in planning and in MRP |
| `MrpManufacturingBatch` | 120 (120 distinct names) | 107 completed, 8 in_production, 5 planned | 81 codes in planning, 36 in production, 0 with `dealId` |
| `InventoryBatch` | 0 | | |
| `MrpProductionBatch` | 0 | | material plan, unrelated to batch codes |

Evidence: `audit/queries/volumes.json`, `audit/queries/status_counts.json`, `audit/queries/orphans_mrp_batches.json`, `audit/queries/orphans_production_vs_planning.json`.

The 39 MRP batches absent from Factory planning (`audit/queries/mrp_batches_not_in_planning.json`): `AB-VB202/VB203`, `AB-VB204/VB205` (satellite batches: Aksakovo parts for Varna batches, a code the planning import cannot parse), `AB128` to `AB136`, `AB138` to `AB143` (2025 Aksakovo months never imported), `AB210` to `AB215` (newer than the last import), `KB134`, `KB160`, `KB163`, `KB178`, `KB312`, `VB91` to `VB95`, `VB98`, `VB99`, `VB118`, `VB119`, `VB202`, `VB203`.

Factory planning coverage (`audit/queries/planning_by_month.json`): Aksakovo March to November 2026 (59 batches, 988 booths), Kazanlak January and February 2025 and January to September 2026 (21 batches, 364 booths), Varna October and November 2025 and May and July 2026 (14 batches, 251 booths). The import is manual, so coverage depends on who pressed the button.

### 2.7 Physical booth identity

| Representation | Rows | Identifier | Links |
|---|---|---|---|
| `FactoryPlanningBooth` | 1,603 | `boothUniqueId`, all 5-digit, all distinct, range 5,515 to 13,244; status 66 ready, 1,537 null | planning batch FK only |
| `FactoryProductionBoothUnit` | 624 | `(batchColorId, unitIndex)`, all status active | regenerated on every rebuild; no booth id |
| `MrpBatchUnit` | 1,224 | `boothIdText`: 980 rows carry a 5-digit id (range 11,660 to 13,315, 944 of them found in planning), 244 rows carry the text `TRUE` | no FK |
| `BoothUnit` (Sales) | 9,132 | one row per sold booth: 9,129 PLANNED, 3 IN_STORAGE; `inventoryUnitId` set on 0 rows | `Deal` FK |
| `InventoryUnit` | 0 | serial number and code | |
| `rp_requests.booth_id` | 366 of 379 set | free text; 157 contain a 5-digit id, 77 of those exist in planning | none |
| `Assembly` | 1,998 | none per booth; 161 rows linked to a deal by `linkedDealId`, 30 carry `visitBooths` JSON | `Deal` FK |

Evidence: `audit/queries/numbering_planning.json`, `audit/queries/numbering_mrp.json`, `audit/queries/numbering_mrp_vs_planning.json`, `audit/queries/mrp_units_no_id_sample.json`, `audit/queries/orphans_boothunit.json`, `audit/queries/rp_booth_ids.json`, `audit/queries/assembly_booths.json`, `audit/queries/numbering_inventory.json`.

The MRP ids reach 13,315 while planning stops at 13,244, so the newest batches exist only in MRP. The `TRUE` values come from the Опаковане tab parser reading a checkbox column for 244 rows. `InventorySerialSequence` is empty (`audit/queries/serial_sequence.json`), so the sequence has not been initialised; `audit/queries/numbering_collisions.json` finds no overlap between planning ids and Inventory serials because Inventory has none yet.

### 2.8 Colours and finishes

| Vocabulary | Distinct values | Top values | Evidence |
|---|---|---|---|
| `FactoryPlanningBooth.colorCode` | 109 | "Pure White" 793, "Pure Black" 511, "Oak Veneer" 72, then RAL codes ("RAL 5002" 10, "RAL 2011" 8) and Egger decor names; only 1 value matches a `FactoryColor` code | `audit/queries/planning_colour_vs_factory.json` |
| `MrpBatchUnit.colour` | 11 | "Pure White" 757, "Pure Black" 377, "Oak Veneer" 69, "Egger H1385 ST40 Natural Casella Oak" 8 | `audit/queries/colours.json` |
| `MrpElementBomLine.colour` | 4 | null 492 (all colours), "Pure White" 302, "Pure Black" 297, "Oak Veneer" 206 | same |
| `FactoryColor.code` | 7 | WHITE, BLACK, OAK, ANTIQUE_ROSE, SANDY_YELLOW, STONE_GREEN, INDIGO_BLUE | same |
| `BoothUnit.finish` (Sales enum) | 4 | CUSTOM 4,196, WHITE_STOCK 2,958, BLACK_STOCK 1,971, LDF_COLOUR 7 | same |
| `QuoteLineItem.finish` + `finishDetails` | 5 enum values | WHITE_STOCK 7,508 lines with 20 detail variants, CUSTOM 2,423 with 72, BLACK_STOCK 1,303 with 13, TBC 1,067 with 63, LDF_COLOUR 15 with 5 | `audit/queries/sales_finish_details.json` |
| `InventoryFinish` | 0 | | |

The planning sheet and MRP use display names, Factory uses codes, Sales uses a five-value bucket plus free text. Nothing maps "Pure White" to WHITE to WHITE_STOCK except the hardcoded `mapColorToFactory` in two Factory files and, from now on, Inventory's mapping table.

### 2.9 Product versions

| Source | Distinct values | Content | Evidence |
|---|---|---|---|
| `FactoryBoothVersionCode.code` | 28 | 7 real version codes ("V2.0.1", "V2.0.2", "Haven 2/4_V1.1", "Camden 2/4_V3.4.3", "Soho/Workstation_V3.4", "V 3.3.1", "V3.4.3" and similar) and 21 free notes from the AKS "бележка" column ("Малки табелки", "Лакиран фурнир", "Зелена изолация", "Врата от AB172 Готова", "Лицата са за C2 12205 AB161") | `audit/queries/versions.json` |
| `MrpRecipeVersion.label` | 4 | V1.4, V3.4.3, V3.4, V1.0 across 7 rows | same |
| `Product.version` | 2 | empty for 736 of 737 products, "WS 1.5" once | same |
| `InventoryUnit.productVersion` | 0 | | |

The version concept is not shared and the Factory column is a note field in practice.

### 2.10 Sites and warehouses

| Table | Rows | Values | Evidence |
|---|---|---|---|
| `FactorySite` | 3 | AKS Аксаково, KAZ Казанлък, VAR Варна | `audit/queries/sites.json` |
| `MrpWarehouse` | 6 | aksakovo, kazanlak, varna, top (Тополи), WH1 (Склад 1), WH2 (Склад 2) | same |
| `InventoryWarehouse` | 1 | TOP Topoli (CENTRAL) | same |
| `InventoryFactory` | 0 | | same |

Three tables name the same three factory sites with three code styles (`AKS` / `aksakovo`), and Topoli appears as an MRP warehouse and as the Inventory central warehouse.

### 2.11 People, credentials and actor fields

| Table | Rows | Link to `User` | Evidence |
|---|---|---|---|
| `User` | 64 | | `audit/queries/people.json` |
| `Employee` | 61 | FK | same |
| `TeamMember` | 64 | FK | `rowcounts.json` |
| `FactoryWorker` (outside schema) | 26 | none | same |
| `clock_workers` | 13 | optional `userId` | same |
| `AssemblyTeamMember` | 4 | none | `audit/queries/people.json` |
| `AssemblyPartner` | 44 | own `codeHash` login | same |
| `StockPartner` | 6 | own `username` and `passwordHash` login | same |
| `SalesRepIdentity` | 15 | FK, versus 27 distinct `Deal.salesRep` strings | same |

Actor fields without a relation (`audit/queries/orphans_deal_actors.json`, `audit/queries/orphans_factory_crew.json`, `audit/queries/rp_user_id_format.json`):

| Field | Set on | Orphans | Note |
|---|---|---|---|
| `Deal.createdByUserId` | 3,333 deals | 0 | joins cleanly; the FK is missing by choice (schema comment at 1591) |
| `DealAuditLog.actorUserId` | 6,484 rows | 0 | same |
| `FactoryProductionEvent.crewWorkerId1` | 452 of 512 events | 0 against `FactoryWorker` | target table is outside the schema |
| `rp_requests.user_id` | 379 of 379 | 379 | holds e-mail addresses (11 distinct), never a `User.id` |

Three login systems coexist: `User` plus `Account` (Google), `AssemblyPartner.codeHash`, `StockPartner.passwordHash`, and `neon_auth` adds a fourth that no MEAVO app appears to use.

### 2.12 Contacts, labels, snapshots and forecast runs

| Pair | Numbers | Evidence |
|---|---|---|
| `DealContact` versus `ClientContact` | 7,024 deal contacts; 6,753 (96 %) share an e-mail with one of the 4,247 client contacts; identical column sets and the same `DealContactKind` enum | `audit/queries/contacts.json` |
| `DealLabel` versus `ClientLabel` | 13 deal labels, 1 client label, no common name | `audit/queries/labels.json` |
| `HubSpotDealSnapshot` versus `SalesCrmSnapshot` | 644 and 308 rows, both keyed by the HubSpot deal id | `rowcounts.json` |
| `SalesForecastRun` versus `SalesForecastManualRun` versus `SalesOpportunityForecastRun` | 39, 0 and 4 rows; the first two have near-identical columns | same |

### 2.13 Scalar keys without a relation

`analysis.json` lists 86 models with 140 id-like scalar fields (`…Id`, `…By`, `…Key`) that have no `@relation`. They fall into five groups:

| Group | Examples | Count (approx.) |
|---|---|---|
| External system ids | `Product.xeroItemId`, `Client.xeroContactId`, `Deal.hubspotDealId`, `User.slackUserId`, `MrpSupplier.zeronId`, `NotificationDelivery.resendMessageId`, `Assembly.googleCalendarEventId` | 30 |
| Storage keys | `storageKey` on 11 attachment tables plus `thumbnailKey`, `pdfStorageKey`, `logoStorageKey`, `signedDocumentKey` | 15 |
| Idempotency and sheet keys | `NotificationOutbox.idempotencyKey`, `ClockEvent.idempotencyKey`, `FactoryProductionEvent.clientEventId`, `FactoryStationIssue.clientIssueId`, `InventoryIntegrationEvent.sourceEventId`, `GatewaySheetRecord.rowKey`, `MrpManufacturingBatch.masterSheetRowKey`, `Inventory*.sourceId`, `FactoryPlanningBooth.boothUniqueId` | 20 |
| Actor ids kept scalar | `Deal.createdByUserId`, `DealAuditLog.actorUserId`, `SalesPayment.recordedById`, `FactorySetting.updatedByUserId`, `RpRequest.userId`, every `…ById` on the Inventory tables (`requestedById`, `releasedById`, `dispatchedById`, `receivedById`, `completedById`, `loadedById`, `packedCheckedById`), `SalesOpportunityForecastRun.requestedById` | 35 |
| Polymorphic or cross-app references | `TaskExternalLink.entityId`, `RpSheetRowMap.entityId`, `RpLifecycleEvent.entityId`, `MrpStockMovement.referenceId`, `MrpInventoryCount.countedThroughBatchId`, `Clock*.stationId` (5 tables, no FK to `FactoryStation`), `Sales*.familyId` and `dealId` snapshots, `MrpManufacturingBatch.dealId`, `InventoryDemand.dealId` and `quoteId`, `BoothUnit.inventoryUnitId` | 40 |

The actor group is the one where a foreign key would cost nothing today: every join tested returned zero orphans. The polymorphic group is where the booth and batch consolidation in the review applies.

### 2.14 Indexes

`audit/queries/unused_indexes.json` lists 200 non-unique indexes with `idx_scan = 0`, 4.3 MB in total, led by `Deal_clientName_idx` (288 KB), `SalesOpportunityForecastItem_hash_idx` (232 KB), `SalesPayment_xeroInvoiceId_idx` (208 KB), three `MrpStockMovement` indexes, `BoothUnit_productId_idx` and `BoothUnit_status_idx`. Because the counters restart with the Neon compute, "zero scans" means zero since the last restart. Re-run the query after a month of uptime, or compare three samples a week apart, before dropping anything. The 200-row cap also means the list may be longer.

### 2.15 Enums and status vocabularies

| Concept | Enums or columns | Values in production |
|---|---|---|
| Batch status | `MrpManufacturingBatchStatus` (planned, in_production, completed, cancelled), `FactoryBatchStatus` (planned, active, paused, done), `FactoryPlanningBatchStatus` (proposed, ready, …), `FactoryPlanningBoothStatus` | MRP 107 completed / 8 in_production / 5 planned; Factory production 4 active / 32 done; planning batches 90 proposed / 4 ready; planning booths 66 ready / 1,537 null |
| Booth status | `BoothUnitStatus`, shared by `BoothUnit.status` and `InventoryUnit.status` | Sales 9,129 PLANNED / 3 IN_STORAGE; Inventory none yet |
| Booth model | `BoothModel`, `BoothProductFamily` | identical 8 values |
| Brand | `Company` (MEAVO, OA) versus `QuotePdfBrand` (MEAVO, OFFICE_ACOUSTICS, OFB) | |
| Locale | `QuestionnaireLocale` enum versus `QuotePdfTemplate.lang` string | |
| Queue status | `NotificationStatus`, `RpSheetSyncStatus`, `MrpSyncStatus`, `InventoryIntegrationStatus` | the same pending, processing, done or failed cycle four times |
| Approval | `RequestStatus` (vacation) versus `FactoryScrapReportStatus` | the same pending, approved, rejected cycle |

Evidence: `audit/queries/status_counts.json` and the schema map.

### 2.16 Repeated patterns: settings, outboxes, audit logs, attachments

| Pattern | Tables | Production rows |
|---|---|---|
| Settings singletons | `XeroIntegrationSettings` 1, `SalesPrioritySettings` 1, `SalesForecastSettings` 1, `FactorySetting` 1 (key/value), `ClockWorkSettings` (`clock_work_settings` 1), `RpAutomationState`, `SheetImportState`, `HubSpotMarketingSync`, `HubSpotCampaignSyncState`, `SalesPaymentSync`, `NotificationEventSetting`, `CompanyProfile` | 12 tables, one row each where populated |
| Outboxes and queues | `NotificationOutbox` 1,550, `RpSheetSyncOutbox` (`sheet_sync_outbox` 980), `InventoryIntegrationEvent` 0, `SalesPriorityWorkItem` 7,400, `SalesOpportunityForecastItem` 1,299 | same column set written five times |
| Audit and event logs | `DealAuditLog` 9,137, `RpLifecycleEvent` (`rp_lifecycle_events` 574), `InventoryAuditEvent` 2, `ClientMergeAudit`, `MrpCorrectionLog` 0, `MrpSyncAttempt` 0, `MrpSheetSyncLog` 6,198, `FactoryPlanningImportRun` 122,894, `SalesOpportunityQualificationEvent` 0, `StockPartnerVisit`, `clock_device_events` 0 | eleven tables with four different actor formats (User FK, scalar user id, e-mail, name) |
| Attachments | `EmployeeDocument`, `GeneratedDocument`, `LibraryAsset`, `ResourceFile`, `SubmissionPhoto`, `DealAttachment`, `ClientEventReceipt`, `FeatureRequestAttachment`, `RpPhoto` (`rp_photos` 15), `FactoryPanelScrapPhoto` 0, `MrpDocument` 0, plus `TaskAttachment` outside the schema | twelve tables with `storageKey` + `fileName` + `mimeType` |
| Sequences | `InventorySerialSequence` 0, `rp_num_sequences` 1, `ip_num_sequences` 1 | |

## 3. Prioritised consolidation list

### 3.1 Safe now (documentation, additive constraints, no app logic change)

| Item | What | Risk |
|---|---|---|
| Documentation | Correct `docs/data-model.md`, `README.md`, the schema header and `docs/architecture.md` (section 4) | none |
| Section headers | Move the 12 Sales priority and forecast models, the 4 `SalesOpportunity*` models and the 4 Factory floor models under the right headers | none, comment-only |
| `BoothModel` enum | Add `ResourceBoothModel.family BoothProductFamily?`, backfill from `boothModel::text`, let Assembly switch, drop `BoothModel` later | low |
| Canonical copies of the outside-schema tables | Add the 10 Factory, 4 MRP and 3 Tasks tables (and the runtime-added Factory columns) to `meavo-db` as additive scripts declared the way production has them; decide whether the 5 Zeron tables join the schema or stay app-private with a documented exception | low once `--diff-only` confirms the shapes |
| `MrpElectricAssemblyVersion` | Apply its script to production or remove the model | low |
| Actor foreign keys | `Deal.createdByUserId`, `DealAuditLog.actorUserId`, `SalesPayment.recordedById`, `FactorySetting.updatedByUserId`, the Inventory `…ById` fields: all join with zero orphans today, so `ON DELETE SET NULL` constraints are safe | low |
| Site links | `MrpWarehouse.siteId` and `InventoryFactory.siteId` to `FactorySite`, backfilled by code (`aksakovo` to `AKS`); keep Topoli as a warehouse | low |
| Retention | Keep the last run per site and month in `FactoryPlanningImportRun` (or stop writing a run for a no-change import); cap `MrpSheetSyncLog` and `NotificationDelivery` | low; 25 MB recovered |
| Bloat | `VACUUM (ANALYZE)` on `SalesOpportunityForecastItem` and `MrpElementBomLine`; check their JSON columns | low |
| App identifiers | Extend `TaskLinkedApp` with inventory and the missing apps; record the `ToolCard.linkedAppKey` mapping in `docs/data-model.md` | low |
| Index review | Re-sample `pg_stat_user_indexes` over a month before dropping any of the 200 unscanned indexes | none until then |

### 3.2 Needs app changes (scheduled in the cross-app review roadmap)

| Item | Apps | Where it is designed |
|---|---|---|
| One booth model catalogue (`BoothFamily`) with FKs from `FactoryBoothModel` and `MrpBoothModel`, labels read from the table | Sales, Factory, MRP, Inventory, Assembly, Stock | review, section 4 |
| One batch master (`ProductionBatch`) with FKs from the four batch tables; satellite codes such as `AB-VB202/VB203` modelled explicitly | Factory, MRP, Inventory | review, sections 4 and 5 |
| One booth identity (`InventoryUnit` as master, the planning id as the serial number); stop regenerating `FactoryProductionBoothUnit`; link `MrpBatchUnit`, `FactoryPlanningBooth`, `BoothUnit`, `rp_requests` | Factory, MRP, Inventory, Sales, RP, Assembly | review, section 4 |
| One finish master (`InventoryFinish`) with aliases for the 109 planning spellings, 11 MRP spellings and 7 Factory codes | Factory, MRP, Inventory, Sales | review, section 4 |
| Version codes: separate real versions from notes; `BoothFamilyVersion` | Factory, MRP, Sales, Inventory | review, section 4 |
| Planning import quality: model code resolution (1,390 nulls), `TRUE` booth ids (244 rows), unparseable satellite codes, "missing booth_unique_id" errors on 7,242 runs | Factory, MRP | review, section 5 |
| `DealContact` into `ClientContact` (96 % duplicates) and `DealLabel*` into `ClientLabel*` | Sales | this audit |
| One `Attachment(ownerType, ownerId, storageKey, fileName, mimeType, size)` for the twelve attachment tables, only if Sales, Assembly, RP and Gateway agree on storage | Gateway, Sales, Assembly, RP, Factory, MRP, Requests, Tasks | this audit |
| Common `actorUserId` plus `actorKind` on the eleven audit tables; keep per-app outboxes but align their columns | all | this audit |
| Per-app role tables (`MrpUserProfile`, `InventoryAccess`, `TaskWorkspaceMember`) onto `ToolCardAccess` roles | Gateway, MRP, Inventory, Tasks | this audit |
| Workers and partners linked to `Employee` or `User` (`FactoryWorker`, `clock_workers`, `AssemblyTeamMember`); RP `user_id` e-mail replaced by a `User` FK | Factory, Clock, Assembly, RP | this audit |
| `MrpProductionBatch` renamed to a material-plan name so "batch" means one thing | MRP | this audit |
| `Panel` catalogue from `FactoryElement.code` with FKs from `MrpBoothElement.code` and `rp_line_items.panel_code` | Factory, MRP, RP | this audit |
| `Company` versus `QuotePdfBrand`; `HubSpotDealSnapshot` versus `SalesCrmSnapshot`; the three forecast run tables | Sales, Gateway | this audit |

### 3.3 Do not touch

- The `User`, `Account`, `Team`, `TeamMember` spine and `ToolCard` / `ToolCardAccess`.
- RP tables with `@@map` snake_case names; their shape is shared with the RP sheet sync.
- Historical scalar ids in the Sales priority and forecast tables (the schema comment at 4680 documents the choice).
- `InventorySerialSequence`, `rp_num_sequences`, `ip_num_sequences`.
- `Questionnaire*`, `Question*` and `SubmissionPhoto` (Assembly surveys).
- `Xero*` mappings and `GatewaySheetRecord`.
- Every `sourceSystem` / `sourceId`, `idempotencyKey`, `clientEventId`, `clientIssueId`, `masterSheetRowKey` and `rowKey`: they are idempotency keys, not links.
- The `neon_auth` schema: it belongs to Neon, not to the MEAVO schema.

## 4. Documentation corrections

Applied in the same pull request as this audit (see the diff for exact wording):

| File | Correction |
|---|---|
| `docs/data-model.md` | Counts: 231 models and 97 enums at v0.100.0, not "~125 models, ~54 enums", with a link to `audit/tables-2026-11.csv`; the domain table gains Sales payments, HubSpot integration, Sales forecasts and Partner stock rows and the missing HR, Xero, Notifications, MRP and Tasks models; the identity-spine paragraph records the known departures (`ClockWorker.userId` optional, `AssemblyTeamMember` without a `User`, partner credential tables, scalar actor ids) |
| `README.md` | Ownership table gains a Xero row, Clock-In, the full Notifications set (`Notification`, `UserNotificationPreference`, `AppAnnouncement`), Xero (6 models), Sales payments, priorities and forecasts, `ProductAvailability` and `ProductAddOnFamilyRestriction`, MRP electric, recipe-version, sync and correction tables, `TaskComment`, `FeatureRequestAttachment`, `PartnerNotificationPreference`, `EmployeeCommission`, `SignatureRequest`, `UsefulLink`, `LibraryVideo`; a new paragraph lists the production tables created outside this schema and the `neon_auth` schema |
| `prisma/schema.prisma` header | Lists every owner app (gateway, hols, assembly, sales, mrp, factory, rp, clock, tasks, requests, stock, inventory) instead of four |
| `docs/architecture.md` | Sibling repository list gains `meavo-tickets` (requests), `meavo-stock`, `meavo-inventory` and a note on the Zeron checker's private schema |

Not changed by this PR: the mis-filed section headers (3.1 lists them as safe work) and `docs/inventory-v1.md`'s "owns the physical stock register" wording, which conflicts with the Partner stock comment at schema line 4639 only until the Stock portal reads Inventory.

## Appendix A. Query index

| File | Purpose |
|---|---|
| `audit/queries/db_size` | database and user-table bytes, server version |
| `audit/queries/schemas`, `audit/queries/tables_non_public` | schemas in use, the 9 `neon_auth` tables |
| `audit/queries/tables_a_l`, `audit/queries/tables_m_z` | `pg_stat_user_tables` sizes and counters (counters unreliable, see caveats) |
| `audit/queries/rowcounts_a_l`, `audit/queries/rowcounts_m_z` | real `count(*)` per public table, merged into `rowcounts.json` |
| `audit/queries/stats_reset` | statistics reset time (none recorded) |
| `audit/queries/unused_indexes` | non-unique indexes with zero scans since the compute started |
| `audit/queries/volumes` | counts of the batch, booth, assembly, deal and RP tables |
| `audit/queries/status_counts` | status distribution of the batch and booth tables |
| `audit/queries/numbering_planning`, `audit/queries/numbering_mrp`, `audit/queries/numbering_inventory`, `audit/queries/numbering_collisions`, `audit/queries/numbering_mrp_vs_planning`, `audit/queries/serial_sequence` | booth id ranges and overlaps |
| `audit/queries/versions` | version values across Product, Factory, MRP and Inventory |
| `audit/queries/models_factory`, `audit/queries/models_mrp`, `audit/queries/models_sales`, `audit/queries/models_family_info`, `audit/queries/mrp_vs_factory_model_names`, `audit/queries/planning_model_codes` | model catalogues and their overlap |
| `audit/queries/colours`, `audit/queries/planning_colour_vs_factory`, `audit/queries/sales_finish_details` | colour and finish vocabularies |
| `audit/queries/sites` | site and warehouse tables |
| `audit/queries/orphans_boothunit`, `audit/queries/orphans_inventory_factory_keys`, `audit/queries/orphans_mrp_batches`, `audit/queries/orphans_production_vs_planning`, `audit/queries/inventory_batches`, `audit/queries/rp_booth_ids`, `audit/queries/rp_user_id_format`, `audit/queries/orphans_deal_actors`, `audit/queries/orphans_factory_crew` | soft-key joins and orphan counts |
| `audit/queries/mrp_batches_not_in_planning`, `audit/queries/planning_by_month`, `audit/queries/mrp_units_no_id_sample` | batch coverage and data-quality samples |
| `audit/queries/contacts`, `audit/queries/labels`, `audit/queries/people`, `audit/queries/assembly_booths`, `audit/queries/boothunit_by_year` | duplication and volume checks |
| `audit/queries/import_runs`, `audit/queries/import_run_errors` | planner import-run volume and error breakdown |
| `audit/tables-2026-11.csv`, `audit/tables-outside-schema-2026-11.csv`, `analysis.json`, `rowcounts.json` | derived inventory produced by `analyze.py` from the files above and the schema copy |

Each `audit/queries/<name>.sql` holds the exact statement; each `<name>.json` the rows returned.

## Appendix B. Factory planning import coverage

From `audit/queries/planning_by_month.json` (batches / booths per imported month tab):

| Site | 2025 | 2026 |
|---|---|---|
| AKS Аксаково | none imported | Mar 10 / 111, Apr 7 / 118, May 5 / 110, Jun 4 / 131, Jul 6 / 117, Aug 5 / 122, Sep 8 / 77, Oct 8 / 120, Nov 6 / 82 (59 batches, 988 booths) |
| KAZ Казанлък | Jan 1 / 26, Feb 1 / 20 | Jan 2 / 48, Feb 1 / 16, Mar 3 / 43, Apr 2 / 45, May 2 / 42, Jun 3 / 46, Jul 2 / 31, Aug 2 / 25, Sep 2 / 22 (21 batches, 364 booths) |
| VAR Варна | Oct 3 / 54, Nov 4 / 79 | May 4 / 50, Jul 3 / 68 (14 batches, 251 booths) |

Totals 94 batches and 1,603 booths. The gaps (Aksakovo 2025 and January to February 2026, Varna 2026 outside May and July) explain most of the 39 MRP batches that have no planning counterpart.

