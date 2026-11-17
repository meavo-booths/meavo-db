-- Standard finishes and the Custom backlog (0.115.0): additive, transactional,
-- idempotent DDL only.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-standard-finishes.sql
--
-- 1. "ProductFinish" gains the five standard finishes Sales used to file under
--    "Laminated Colour": OAK, SAND_YELLOW, INDIGO_BLUE, ANTIQUE_ROSE, STONE_GREEN.
--    LDF_COLOUR stays for old rows. Values added here cannot be used as literals
--    until this transaction commits; nothing below uses them.
--    Every app that reads QuoteLineItem or BoothUnit through Prisma (Sales,
--    Inventory, Assembly) must run a client generated from 0.115.0 or later
--    BEFORE any row carries a new value: an older client fails on a value it
--    does not know. Apply this file, release those apps, and only then run
--    scripts/convert-laminated-colour-finishes.sql or offer the values in Sales.
-- 2. "InventoryDemandLine" gains the brief fields of the Custom backlog: when a
--    made-to-order line was briefed, by whom, to which factory and batch.
BEGIN;

-- AlterEnum
ALTER TYPE "ProductFinish" ADD VALUE IF NOT EXISTS 'OAK';
ALTER TYPE "ProductFinish" ADD VALUE IF NOT EXISTS 'SAND_YELLOW';
ALTER TYPE "ProductFinish" ADD VALUE IF NOT EXISTS 'INDIGO_BLUE';
ALTER TYPE "ProductFinish" ADD VALUE IF NOT EXISTS 'ANTIQUE_ROSE';
ALTER TYPE "ProductFinish" ADD VALUE IF NOT EXISTS 'STONE_GREEN';

-- AlterTable
ALTER TABLE "InventoryDemandLine"
  ADD COLUMN IF NOT EXISTS "briefedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "briefedById" TEXT,
  ADD COLUMN IF NOT EXISTS "briefFactoryId" TEXT,
  ADD COLUMN IF NOT EXISTS "briefBatchCode" TEXT,
  ADD COLUMN IF NOT EXISTS "briefNote" TEXT;

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemandLine_briefFactoryId_idx"
  ON "InventoryDemandLine"("briefFactoryId");

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryDemandLine" ADD CONSTRAINT "InventoryDemandLine_briefFactoryId_fkey"
    FOREIGN KEY ("briefFactoryId") REFERENCES "InventoryFactory"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
