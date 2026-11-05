-- Production batch master (cross-app data review 2026-11, release 1, script 2 of 4):
-- additive, transactional, idempotent.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-production-batch-master.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-production-batch-master.sql --schema prisma/schema.prisma
-- Required existing objects: scripts/add-booth-family-catalog.sql, scripts/add-inventory-v1.sql,
-- FactorySite, FactoryPlanningBatch, FactoryPlanningBooth, FactoryProductionBatch,
-- FactoryProductionBatchColor, MrpManufacturingBatch, MrpWarehouse.
--
-- Creates ProductionBatch (one row per batch code, owned by Inventory) and the
-- nullable links from the four batch copies, plus the site links of
-- MrpWarehouse and InventoryFactory to FactorySite.
-- Master rows are seeded in this order, each code once (ON CONFLICT DO NOTHING):
--   1. FactoryPlanningBatch (carries site, month, deadline, US flag);
--   2. FactoryProductionBatch codes missing from planning;
--   3. MrpManufacturingBatch names that are plain codes (AB210, KB134); satellite
--      rows such as "AB-VB202/VB203" get no master and stay unlinked;
--   4. InventoryBatch numbers that are plain codes and whose site resolves.
-- Site of rows 2 to 4: the MRP row-key prefix ("AKS:AB193"), the MRP warehouse
-- or InventoryFactory site, else the code prefix (AB -> AKS, KB -> KAZ,
-- VB -> VAR; true for all 94 production planning batches on 5 November 2026).
-- Status is the most advanced state any copy reports (cancelled only when no
-- copy shows progress): planning proposed/planned/active/paused/ready, Factory
-- planned/active/paused/done, MRP planned/in_production/completed map to
-- PROPOSED/PLANNED/IN_PRODUCTION/READY; an Inventory-only batch is READY.
-- versionCode stays null: Factory version codes are mostly free notes (audit 2.9).
-- Existing master rows and links are never updated, so reruns change nothing.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "ProductionBatchStatus" AS ENUM ('PROPOSED', 'PLANNED', 'IN_PRODUCTION', 'PARTIALLY_READY', 'READY', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "ProductionBatch" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "siteId" TEXT NOT NULL,
    "familyCode" TEXT,
    "versionCode" TEXT,
    "productionYear" INTEGER,
    "productionMonth" INTEGER,
    "plannedQty" INTEGER,
    "plannedStart" DATE,
    "plannedEnd" DATE,
    "originalDeadline" DATE,
    "isUsMarket" BOOLEAN,
    "status" "ProductionBatchStatus" NOT NULL DEFAULT 'PLANNED',
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProductionBatch_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ProductionBatch_code_key" ON "ProductionBatch"("code");
CREATE UNIQUE INDEX IF NOT EXISTS "ProductionBatch_sourceSystem_sourceId_key" ON "ProductionBatch"("sourceSystem", "sourceId");
CREATE INDEX IF NOT EXISTS "ProductionBatch_siteId_productionYear_productionMonth_idx" ON "ProductionBatch"("siteId", "productionYear", "productionMonth");
CREATE INDEX IF NOT EXISTS "ProductionBatch_status_idx" ON "ProductionBatch"("status");

-- AlterTable: batch links and site links.
ALTER TABLE "FactoryPlanningBatch" ADD COLUMN IF NOT EXISTS "productionBatchId" TEXT;
ALTER TABLE "FactoryProductionBatch" ADD COLUMN IF NOT EXISTS "productionBatchId" TEXT;
ALTER TABLE "MrpManufacturingBatch" ADD COLUMN IF NOT EXISTS "productionBatchId" TEXT;
ALTER TABLE "InventoryBatch" ADD COLUMN IF NOT EXISTS "productionBatchId" TEXT;
ALTER TABLE "MrpWarehouse" ADD COLUMN IF NOT EXISTS "siteId" TEXT;
ALTER TABLE "InventoryFactory" ADD COLUMN IF NOT EXISTS "siteId" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPlanningBatch_productionBatchId_key" ON "FactoryPlanningBatch"("productionBatchId");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryProductionBatch_productionBatchId_key" ON "FactoryProductionBatch"("productionBatchId");
CREATE UNIQUE INDEX IF NOT EXISTS "MrpManufacturingBatch_productionBatchId_key" ON "MrpManufacturingBatch"("productionBatchId");
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryBatch_productionBatchId_key" ON "InventoryBatch"("productionBatchId");
CREATE INDEX IF NOT EXISTS "MrpWarehouse_siteId_idx" ON "MrpWarehouse"("siteId");
CREATE INDEX IF NOT EXISTS "InventoryFactory_siteId_idx" ON "InventoryFactory"("siteId");

-- Backfill site links. Topoli (top), WH1 and WH2 are warehouses, not factory sites.
UPDATE "MrpWarehouse" w
SET "siteId" = s."id"
FROM (VALUES ('aksakovo', 'AKS'), ('kazanlak', 'KAZ'), ('varna', 'VAR')) AS map("warehouseCode", "siteCode"),
     "FactorySite" s
WHERE w."siteId" IS NULL
  AND (lower(btrim(w."code")) = map."warehouseCode" OR upper(btrim(w."code")) = map."siteCode")
  AND s."code" = map."siteCode";

UPDATE "InventoryFactory" f
SET "siteId" = s."id"
FROM (VALUES ('aksakovo', 'AKS'), ('kazanlak', 'KAZ'), ('varna', 'VAR')) AS map("warehouseCode", "siteCode"),
     "FactorySite" s
WHERE f."siteId" IS NULL
  AND (lower(btrim(f."code")) = map."warehouseCode" OR upper(btrim(f."code")) = map."siteCode")
  AND s."code" = map."siteCode";

-- Working tables for this transaction only.
CREATE TEMP TABLE "_pb_prefix" ("prefix" TEXT PRIMARY KEY, "siteCode" TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO "_pb_prefix" VALUES ('AB', 'AKS'), ('KB', 'KAZ'), ('VB', 'VAR');

-- Status rank per code across the three sheet-fed copies:
-- 0 cancelled, 1 proposed, 2 planned, 3 in production, 5 ready.
CREATE TEMP TABLE "_pb_status" ON COMMIT DROP AS
SELECT "code", max("rank") AS "rank"
FROM (
  SELECT "batchCode" AS "code",
         CASE "status"::text WHEN 'proposed' THEN 1 WHEN 'planned' THEN 2 WHEN 'active' THEN 3
                             WHEN 'paused' THEN 3 WHEN 'ready' THEN 5 ELSE 0 END AS "rank"
  FROM "FactoryPlanningBatch"
  UNION ALL
  SELECT "batchCode",
         CASE "status"::text WHEN 'planned' THEN 2 WHEN 'active' THEN 3 WHEN 'paused' THEN 3
                             WHEN 'done' THEN 5 ELSE 0 END
  FROM "FactoryProductionBatch"
  UNION ALL
  SELECT "name",
         CASE "status"::text WHEN 'planned' THEN 2 WHEN 'in_production' THEN 3
                             WHEN 'completed' THEN 5 ELSE 0 END
  FROM "MrpManufacturingBatch"
) s
GROUP BY "code";

-- 1. Planning batches.
INSERT INTO "ProductionBatch"
  ("id", "code", "siteId", "familyCode", "productionYear", "productionMonth", "plannedQty",
   "plannedStart", "plannedEnd", "originalDeadline", "isUsMarket", "status",
   "sourceSystem", "sourceId", "createdAt", "updatedAt")
SELECT
  'cm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 23),
  p."batchCode",
  p."siteId",
  COALESCE(bf_plan."code", fbm."familyCode", mrp."familyCode"),
  p."productionYear",
  p."productionMonth",
  COALESCE(NULLIF(booths."n", 0), NULLIF(colours."qty", 0), NULLIF(mrp."qty", 0)),
  COALESCE(p."plannedStart", fp."plannedStart"),
  COALESCE(p."plannedEnd", fp."plannedEnd"),
  p."originalDeadline",
  p."isUsMarket",
  (CASE st."rank" WHEN 0 THEN 'CANCELLED' WHEN 1 THEN 'PROPOSED' WHEN 2 THEN 'PLANNED'
                  WHEN 3 THEN 'IN_PRODUCTION' WHEN 4 THEN 'PARTIALLY_READY' WHEN 5 THEN 'READY'
                  ELSE 'PROPOSED' END)::"ProductionBatchStatus",
  'sheet',
  s."code" || ':' || p."batchCode",
  p."createdAt",
  CURRENT_TIMESTAMP
FROM "FactoryPlanningBatch" p
JOIN "FactorySite" s ON s."id" = p."siteId"
LEFT JOIN "BoothFamily" bf_plan ON bf_plan."factoryCode" = p."modelCode"
LEFT JOIN "FactoryProductionBatch" fp ON fp."batchCode" = p."batchCode"
LEFT JOIN "FactoryBoothModel" fbm ON fbm."id" = fp."boothModelId"
LEFT JOIN LATERAL (
  SELECT mb."qty", bm."familyCode"
  FROM "MrpManufacturingBatch" mb
  LEFT JOIN "MrpBoothModel" bm ON bm."id" = mb."boothModelId"
  WHERE mb."name" = p."batchCode"
  ORDER BY mb."updatedAt" DESC, mb."id"
  LIMIT 1
) mrp ON true
LEFT JOIN LATERAL (
  SELECT count(*)::int AS "n" FROM "FactoryPlanningBooth" b WHERE b."planningBatchId" = p."id"
) booths ON true
LEFT JOIN LATERAL (
  SELECT sum(c."targetBoothQty")::int AS "qty" FROM "FactoryProductionBatchColor" c WHERE c."batchId" = fp."id"
) colours ON true
LEFT JOIN "_pb_status" st ON st."code" = p."batchCode"
ON CONFLICT DO NOTHING;

-- 2. Factory production batches missing from planning.
INSERT INTO "ProductionBatch"
  ("id", "code", "siteId", "familyCode", "plannedQty", "plannedStart", "plannedEnd", "status",
   "sourceSystem", "sourceId", "createdAt", "updatedAt")
SELECT
  'cm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 23),
  fp."batchCode",
  site."id",
  COALESCE(fbm."familyCode", mrp."familyCode"),
  COALESCE(NULLIF(colours."qty", 0), NULLIF(mrp."qty", 0)),
  fp."plannedStart",
  fp."plannedEnd",
  (CASE st."rank" WHEN 0 THEN 'CANCELLED' WHEN 1 THEN 'PROPOSED' WHEN 2 THEN 'PLANNED'
                  WHEN 3 THEN 'IN_PRODUCTION' WHEN 4 THEN 'PARTIALLY_READY' WHEN 5 THEN 'READY'
                  ELSE 'PLANNED' END)::"ProductionBatchStatus",
  'sheet',
  site."code" || ':' || fp."batchCode",
  fp."createdAt",
  CURRENT_TIMESTAMP
FROM "FactoryProductionBatch" fp
LEFT JOIN "FactoryBoothModel" fbm ON fbm."id" = fp."boothModelId"
LEFT JOIN LATERAL (
  SELECT mb."qty", bm."familyCode", mb."masterSheetRowKey", mb."warehouseId"
  FROM "MrpManufacturingBatch" mb
  LEFT JOIN "MrpBoothModel" bm ON bm."id" = mb."boothModelId"
  WHERE mb."name" = fp."batchCode"
  ORDER BY mb."updatedAt" DESC, mb."id"
  LIMIT 1
) mrp ON true
LEFT JOIN "MrpWarehouse" w ON w."id" = mrp."warehouseId"
LEFT JOIN LATERAL (
  SELECT sum(c."targetBoothQty")::int AS "qty" FROM "FactoryProductionBatchColor" c WHERE c."batchId" = fp."id"
) colours ON true
JOIN LATERAL (
  SELECT fs."id", fs."code"
  FROM "FactorySite" fs
  WHERE fs."code" = split_part(mrp."masterSheetRowKey", ':', 1)
     OR fs."id" = w."siteId"
     OR fs."code" = (SELECT x."siteCode" FROM "_pb_prefix" x
                     WHERE x."prefix" = substring(fp."batchCode" from '^([A-Z]+)[0-9]+$'))
  ORDER BY (fs."code" = split_part(mrp."masterSheetRowKey", ':', 1)) DESC NULLS LAST,
           (fs."id" = w."siteId") DESC NULLS LAST
  LIMIT 1
) site ON true
LEFT JOIN "_pb_status" st ON st."code" = fp."batchCode"
WHERE NOT EXISTS (SELECT 1 FROM "ProductionBatch" pb WHERE pb."code" = fp."batchCode")
ON CONFLICT DO NOTHING;

-- 3. MRP batches whose name is a plain code (satellite rows are skipped).
INSERT INTO "ProductionBatch"
  ("id", "code", "siteId", "familyCode", "plannedQty", "status",
   "sourceSystem", "sourceId", "createdAt", "updatedAt")
SELECT
  'cm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 23),
  mb."name",
  site."id",
  bm."familyCode",
  NULLIF(mb."qty", 0),
  (CASE st."rank" WHEN 0 THEN 'CANCELLED' WHEN 1 THEN 'PROPOSED' WHEN 2 THEN 'PLANNED'
                  WHEN 3 THEN 'IN_PRODUCTION' WHEN 4 THEN 'PARTIALLY_READY' WHEN 5 THEN 'READY'
                  ELSE 'PLANNED' END)::"ProductionBatchStatus",
  'sheet',
  mb."masterSheetRowKey",
  mb."createdAt",
  CURRENT_TIMESTAMP
FROM (
  SELECT DISTINCT ON ("name") *
  FROM "MrpManufacturingBatch"
  WHERE "name" ~ '^[A-Z]+[0-9]+$'
  ORDER BY "name", "updatedAt" DESC, "id"
) mb
LEFT JOIN "MrpBoothModel" bm ON bm."id" = mb."boothModelId"
LEFT JOIN "MrpWarehouse" w ON w."id" = mb."warehouseId"
JOIN LATERAL (
  SELECT fs."id"
  FROM "FactorySite" fs
  WHERE fs."code" = split_part(mb."masterSheetRowKey", ':', 1)
     OR fs."id" = w."siteId"
     OR fs."code" = (SELECT x."siteCode" FROM "_pb_prefix" x
                     WHERE x."prefix" = substring(mb."name" from '^([A-Z]+)[0-9]+$'))
  ORDER BY (fs."code" = split_part(mb."masterSheetRowKey", ':', 1)) DESC NULLS LAST,
           (fs."id" = w."siteId") DESC NULLS LAST
  LIMIT 1
) site ON true
LEFT JOIN "_pb_status" st ON st."code" = mb."name"
WHERE NOT EXISTS (SELECT 1 FROM "ProductionBatch" pb WHERE pb."code" = mb."name")
ON CONFLICT DO NOTHING;

-- 4. Inventory batches whose number is a plain code and whose site resolves.
--    The family is set only when every unit of the batch has the same one.
INSERT INTO "ProductionBatch"
  ("id", "code", "siteId", "familyCode", "status",
   "sourceSystem", "sourceId", "createdAt", "updatedAt")
SELECT
  'cm' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 23),
  ib."batchNumber",
  site."id",
  fam."familyCode",
  'READY'::"ProductionBatchStatus",
  'inventory',
  ib."id",
  ib."createdAt",
  CURRENT_TIMESTAMP
FROM (
  SELECT DISTINCT ON (btrim("batchNumber")) "id", btrim("batchNumber") AS "batchNumber", "factoryId", "createdAt"
  FROM "InventoryBatch"
  WHERE btrim("batchNumber") ~ '^[A-Z]+[0-9]+$'
  ORDER BY btrim("batchNumber"), "createdAt", "id"
) ib
JOIN "InventoryFactory" f ON f."id" = ib."factoryId"
JOIN LATERAL (
  SELECT fs."id"
  FROM "FactorySite" fs
  WHERE fs."id" = f."siteId"
     OR fs."code" = (SELECT x."siteCode" FROM "_pb_prefix" x
                     WHERE x."prefix" = substring(ib."batchNumber" from '^([A-Z]+)[0-9]+$'))
  ORDER BY (fs."id" = f."siteId") DESC NULLS LAST
  LIMIT 1
) site ON true
LEFT JOIN LATERAL (
  SELECT CASE WHEN count(DISTINCT u."family") = 1 THEN min(bf."code") END AS "familyCode"
  FROM "InventoryUnit" u
  JOIN "BoothFamily" bf ON bf."family" = u."family"
  WHERE u."batchId" = ib."id"
) fam ON true
WHERE NOT EXISTS (SELECT 1 FROM "ProductionBatch" pb WHERE pb."code" = ib."batchNumber")
ON CONFLICT DO NOTHING;

-- Backfill links by code. One copy per master row; links set by hand are kept.
UPDATE "FactoryPlanningBatch" p
SET "productionBatchId" = pb."id"
FROM "ProductionBatch" pb
WHERE p."productionBatchId" IS NULL
  AND pb."code" = p."batchCode"
  AND NOT EXISTS (SELECT 1 FROM "FactoryPlanningBatch" x WHERE x."productionBatchId" = pb."id");

UPDATE "FactoryProductionBatch" fp
SET "productionBatchId" = pb."id"
FROM "ProductionBatch" pb
WHERE fp."productionBatchId" IS NULL
  AND pb."code" = fp."batchCode"
  AND NOT EXISTS (SELECT 1 FROM "FactoryProductionBatch" x WHERE x."productionBatchId" = pb."id");

UPDATE "MrpManufacturingBatch" mb
SET "productionBatchId" = pb."id"
FROM (
  SELECT DISTINCT ON ("name") "id", "name"
  FROM "MrpManufacturingBatch"
  WHERE "productionBatchId" IS NULL
  ORDER BY "name", "updatedAt" DESC, "id"
) pick
JOIN "ProductionBatch" pb ON pb."code" = pick."name"
WHERE mb."id" = pick."id"
  AND NOT EXISTS (SELECT 1 FROM "MrpManufacturingBatch" x WHERE x."productionBatchId" = pb."id");

UPDATE "InventoryBatch" ib
SET "productionBatchId" = pb."id"
FROM (
  SELECT DISTINCT ON (btrim("batchNumber")) "id", btrim("batchNumber") AS "batchNumber"
  FROM "InventoryBatch"
  WHERE "productionBatchId" IS NULL
  ORDER BY btrim("batchNumber"), "createdAt", "id"
) pick
JOIN "ProductionBatch" pb ON pb."code" = pick."batchNumber"
WHERE ib."id" = pick."id"
  AND NOT EXISTS (SELECT 1 FROM "InventoryBatch" x WHERE x."productionBatchId" = pb."id");

-- AddForeignKey (guarded).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ProductionBatch_siteId_fkey' AND conrelid = '"ProductionBatch"'::regclass) THEN
    ALTER TABLE "ProductionBatch" ADD CONSTRAINT "ProductionBatch_siteId_fkey"
      FOREIGN KEY ("siteId") REFERENCES "FactorySite"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ProductionBatch_familyCode_fkey' AND conrelid = '"ProductionBatch"'::regclass) THEN
    ALTER TABLE "ProductionBatch" ADD CONSTRAINT "ProductionBatch_familyCode_fkey"
      FOREIGN KEY ("familyCode") REFERENCES "BoothFamily"("code") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FactoryPlanningBatch_productionBatchId_fkey' AND conrelid = '"FactoryPlanningBatch"'::regclass) THEN
    ALTER TABLE "FactoryPlanningBatch" ADD CONSTRAINT "FactoryPlanningBatch_productionBatchId_fkey"
      FOREIGN KEY ("productionBatchId") REFERENCES "ProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FactoryProductionBatch_productionBatchId_fkey' AND conrelid = '"FactoryProductionBatch"'::regclass) THEN
    ALTER TABLE "FactoryProductionBatch" ADD CONSTRAINT "FactoryProductionBatch_productionBatchId_fkey"
      FOREIGN KEY ("productionBatchId") REFERENCES "ProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MrpManufacturingBatch_productionBatchId_fkey' AND conrelid = '"MrpManufacturingBatch"'::regclass) THEN
    ALTER TABLE "MrpManufacturingBatch" ADD CONSTRAINT "MrpManufacturingBatch_productionBatchId_fkey"
      FOREIGN KEY ("productionBatchId") REFERENCES "ProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'InventoryBatch_productionBatchId_fkey' AND conrelid = '"InventoryBatch"'::regclass) THEN
    ALTER TABLE "InventoryBatch" ADD CONSTRAINT "InventoryBatch_productionBatchId_fkey"
      FOREIGN KEY ("productionBatchId") REFERENCES "ProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MrpWarehouse_siteId_fkey' AND conrelid = '"MrpWarehouse"'::regclass) THEN
    ALTER TABLE "MrpWarehouse" ADD CONSTRAINT "MrpWarehouse_siteId_fkey"
      FOREIGN KEY ("siteId") REFERENCES "FactorySite"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'InventoryFactory_siteId_fkey' AND conrelid = '"InventoryFactory"'::regclass) THEN
    ALTER TABLE "InventoryFactory" ADD CONSTRAINT "InventoryFactory_siteId_fkey"
      FOREIGN KEY ("siteId") REFERENCES "FactorySite"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

COMMIT;
