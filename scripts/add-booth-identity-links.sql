-- Booth identity links (cross-app data review 2026-11, release 1, script 3 of 4):
-- additive, transactional, idempotent.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-booth-identity-links.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-booth-identity-links.sql --schema prisma/schema.prisma
-- Required existing objects: scripts/add-production-batch-master.sql, scripts/add-inventory-v1.sql,
-- scripts/add-booth-unit-inventory-link.sql, FactoryPlanningBooth, FactoryProductionBoothUnit, MrpBatchUnit.
--
-- InventoryUnit is the single physical booth; its serialNumber is the planning
-- sheet's 5-digit booth id. This script adds the nullable links from the other
-- copies and InventoryUnit.productionBatchId / plannedSortOrder:
--   InventoryUnit.productionBatchId   from its InventoryBatch, else from the linked planning booth
--   InventoryUnit.plannedSortOrder    from the linked planning booth in the same master batch
--   FactoryPlanningBooth.inventoryUnitId        serialNumber = boothUniqueId::int, where a unit exists
--   FactoryProductionBoothUnit.inventoryUnitId  column only; set later by the stable materialise step
--   MrpBatchUnit.inventoryUnitId      the 5-digit id in boothIdText ("SO 11704 AB146"); rows that
--                                     hold "TRUE" (244 in production on 5 November 2026) or another
--                                     non-id stay null; an id that appears twice is skipped; when
--                                     both sides know their master batch, it must be the same one
--   BoothUnit.inventoryUnitId         becomes a real FK with ON DELETE SET NULL; the script stops
--                                     with an error if a value has no InventoryUnit
-- Backfills fill NULLs only, so a rerun never changes a link set by hand.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- AlterTable
ALTER TABLE "InventoryUnit"
  ADD COLUMN IF NOT EXISTS "productionBatchId" TEXT,
  ADD COLUMN IF NOT EXISTS "plannedSortOrder" INTEGER;
ALTER TABLE "FactoryPlanningBooth" ADD COLUMN IF NOT EXISTS "inventoryUnitId" TEXT;
ALTER TABLE "FactoryProductionBoothUnit" ADD COLUMN IF NOT EXISTS "inventoryUnitId" TEXT;
ALTER TABLE "MrpBatchUnit" ADD COLUMN IF NOT EXISTS "inventoryUnitId" TEXT;

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_productionBatchId_plannedSortOrder_idx"
  ON "InventoryUnit"("productionBatchId", "plannedSortOrder");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPlanningBooth_inventoryUnitId_key" ON "FactoryPlanningBooth"("inventoryUnitId");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryProductionBoothUnit_inventoryUnitId_key" ON "FactoryProductionBoothUnit"("inventoryUnitId");
CREATE UNIQUE INDEX IF NOT EXISTS "MrpBatchUnit_inventoryUnitId_key" ON "MrpBatchUnit"("inventoryUnitId");

-- Backfill InventoryUnit.productionBatchId from the unit's InventoryBatch.
UPDATE "InventoryUnit" u
SET "productionBatchId" = ib."productionBatchId"
FROM "InventoryBatch" ib
WHERE u."productionBatchId" IS NULL
  AND ib."id" = u."batchId"
  AND ib."productionBatchId" IS NOT NULL;

-- Backfill FactoryPlanningBooth by booth id (no leading zero, so one text per number).
UPDATE "FactoryPlanningBooth" b
SET "inventoryUnitId" = u."id"
FROM "InventoryUnit" u
WHERE b."inventoryUnitId" IS NULL
  AND b."boothUniqueId" ~ '^[1-9][0-9]{0,8}$'
  AND u."serialNumber" = b."boothUniqueId"::int
  AND NOT EXISTS (SELECT 1 FROM "FactoryPlanningBooth" x WHERE x."inventoryUnitId" = u."id");

-- Units linked to a planning booth take its master batch and sort order when they have none.
UPDATE "InventoryUnit" u
SET "productionBatchId" = p."productionBatchId"
FROM "FactoryPlanningBooth" b
JOIN "FactoryPlanningBatch" p ON p."id" = b."planningBatchId"
WHERE b."inventoryUnitId" = u."id"
  AND u."productionBatchId" IS NULL
  AND p."productionBatchId" IS NOT NULL;

UPDATE "InventoryUnit" u
SET "plannedSortOrder" = b."sortOrder"
FROM "FactoryPlanningBooth" b
JOIN "FactoryPlanningBatch" p ON p."id" = b."planningBatchId"
WHERE b."inventoryUnitId" = u."id"
  AND u."plannedSortOrder" IS NULL
  AND u."productionBatchId" = p."productionBatchId";

-- Backfill MrpBatchUnit by the 5-digit id in boothIdText.
WITH parsed AS (
  SELECT mu."id",
         substring(mu."boothIdText" from '(?:^|[^0-9])([1-9][0-9]{4})(?:[^0-9]|$)')::int AS "serial",
         mb."productionBatchId"
  FROM "MrpBatchUnit" mu
  JOIN "MrpManufacturingBatch" mb ON mb."id" = mu."manufacturingBatchId"
  WHERE mu."inventoryUnitId" IS NULL
    AND mu."boothIdText" ~ '(^|[^0-9])[1-9][0-9]{4}([^0-9]|$)'
),
single AS (
  SELECT p.* FROM parsed p
  WHERE NOT EXISTS (SELECT 1 FROM parsed q WHERE q."serial" = p."serial" AND q."id" <> p."id")
)
UPDATE "MrpBatchUnit" mu
SET "inventoryUnitId" = u."id"
FROM single s
JOIN "InventoryUnit" u ON u."serialNumber" = s."serial"
WHERE mu."id" = s."id"
  AND (u."productionBatchId" IS NULL OR s."productionBatchId" IS NULL OR u."productionBatchId" = s."productionBatchId")
  AND NOT EXISTS (SELECT 1 FROM "MrpBatchUnit" x WHERE x."inventoryUnitId" = u."id");

-- AddForeignKey (guarded). BoothUnit is checked first so a dangling value fails loudly.
DO $$
DECLARE dangling integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'InventoryUnit_productionBatchId_fkey' AND conrelid = '"InventoryUnit"'::regclass) THEN
    ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_productionBatchId_fkey"
      FOREIGN KEY ("productionBatchId") REFERENCES "ProductionBatch"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FactoryPlanningBooth_inventoryUnitId_fkey' AND conrelid = '"FactoryPlanningBooth"'::regclass) THEN
    ALTER TABLE "FactoryPlanningBooth" ADD CONSTRAINT "FactoryPlanningBooth_inventoryUnitId_fkey"
      FOREIGN KEY ("inventoryUnitId") REFERENCES "InventoryUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FactoryProductionBoothUnit_inventoryUnitId_fkey' AND conrelid = '"FactoryProductionBoothUnit"'::regclass) THEN
    ALTER TABLE "FactoryProductionBoothUnit" ADD CONSTRAINT "FactoryProductionBoothUnit_inventoryUnitId_fkey"
      FOREIGN KEY ("inventoryUnitId") REFERENCES "InventoryUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'MrpBatchUnit_inventoryUnitId_fkey' AND conrelid = '"MrpBatchUnit"'::regclass) THEN
    ALTER TABLE "MrpBatchUnit" ADD CONSTRAINT "MrpBatchUnit_inventoryUnitId_fkey"
      FOREIGN KEY ("inventoryUnitId") REFERENCES "InventoryUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'BoothUnit_inventoryUnitId_fkey' AND conrelid = '"BoothUnit"'::regclass) THEN
    SELECT count(*) INTO dangling
    FROM "BoothUnit" b
    WHERE b."inventoryUnitId" IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM "InventoryUnit" u WHERE u."id" = b."inventoryUnitId");
    IF dangling > 0 THEN
      RAISE EXCEPTION 'BoothUnit has % inventoryUnitId value(s) without an InventoryUnit; fix them before adding BoothUnit_inventoryUnitId_fkey', dangling;
    END IF;
    ALTER TABLE "BoothUnit" ADD CONSTRAINT "BoothUnit_inventoryUnitId_fkey"
      FOREIGN KEY ("inventoryUnitId") REFERENCES "InventoryUnit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

COMMIT;
