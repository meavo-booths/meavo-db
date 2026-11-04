-- Inventory export lines: additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: npx prisma db execute --file scripts/add-inventory-export-lines.sql --schema prisma/schema.prisma
-- Required existing objects: scripts/add-inventory-v1.sql (InventoryAllocation,
-- InventoryUnit, InventoryDemand, InventoryWarehouse, InventoryTransfer).
-- One row per allocated booth in the weekly export list; loadedAt marks dispatch.
-- The composite FK (allocationId, unitId) guarantees a line never names a booth
-- other than its allocation's. The pallet number stays in InventoryPalletContent.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryExportDestination" AS ENUM ('WAREHOUSE', 'DIRECT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryExportLine" (
    "id" TEXT NOT NULL,
    "allocationId" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "demandId" TEXT NOT NULL,
    "exportWeek" TEXT,
    "destinationKind" "InventoryExportDestination",
    "destinationWarehouseId" TEXT,
    "destinationLabel" TEXT NOT NULL DEFAULT '',
    "loadedAt" TIMESTAMP(3),
    "loadedById" TEXT,
    "transferId" TEXT,
    "labelsPrintedAt" TIMESTAMP(3),
    "spareParts" TEXT NOT NULL DEFAULT '',
    "workshopNote" TEXT NOT NULL DEFAULT '',
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryExportLine_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryExportLine_allocationId_key" ON "InventoryExportLine"("allocationId");
-- The pair backs the composite one-to-one relation in the Prisma schema.
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryExportLine_allocationId_unitId_key" ON "InventoryExportLine"("allocationId", "unitId");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_demandId_idx" ON "InventoryExportLine"("demandId");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_unitId_idx" ON "InventoryExportLine"("unitId");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_exportWeek_idx" ON "InventoryExportLine"("exportWeek");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_loadedAt_idx" ON "InventoryExportLine"("loadedAt");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_destinationWarehouseId_idx" ON "InventoryExportLine"("destinationWarehouseId");
CREATE INDEX IF NOT EXISTS "InventoryExportLine_transferId_idx" ON "InventoryExportLine"("transferId");

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_allocationId_unitId_fkey" FOREIGN KEY ("allocationId", "unitId") REFERENCES "InventoryAllocation"("id", "unitId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_demandId_fkey" FOREIGN KEY ("demandId") REFERENCES "InventoryDemand"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_destinationWarehouseId_fkey" FOREIGN KEY ("destinationWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_transferId_fkey" FOREIGN KEY ("transferId") REFERENCES "InventoryTransfer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- A loaded line has a frozen destination; a warehouse destination names the warehouse.
DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_loaded_destination_check"
    CHECK ("loadedAt" IS NULL OR "destinationKind" IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_warehouse_destination_check"
    CHECK ("destinationKind"::text IS DISTINCT FROM 'WAREHOUSE' OR "destinationWarehouseId" IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryExportLine" ADD CONSTRAINT "InventoryExportLine_week_shape_check"
    CHECK ("exportWeek" IS NULL OR "exportWeek" ~ '^[0-9]{4}-W[0-9]{2}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
