-- Inventory V1: additive, transactional, idempotent domain DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: npx prisma db execute --file scripts/add-inventory-v1.sql --schema prisma/schema.prisma
-- Required existing objects: User, BoothProductFamily, BoothUnitStatus.
-- This script does not seed stock, users, warehouse configuration or sequence rows.
-- SQL-only constraints/indexes below are mandatory; db push alone is insufficient.
-- Application code lazily inserts singleton InventorySerialSequence("global",40000)
-- and increments it atomically within the same transaction as confirmed allocation.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryWarehouseKind" AS ENUM ('LOCAL', 'CENTRAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryVoltage" AS ENUM ('UNKNOWN', 'V110_120', 'V220_240');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryRole" AS ENUM ('VIEWER', 'SALES', 'OPS_PRODUCT', 'WAREHOUSE', 'FACTORY', 'ADMIN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryDemandKind" AS ENUM ('QUOTE', 'DEAL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryDemandState" AS ENUM ('OPEN', 'WON', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryAllocationKind" AS ENUM ('QUOTE_HOLD', 'COMMITTED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryAllocationStatus" AS ENUM ('ACTIVE', 'RELEASED', 'EXPIRED', 'FULFILLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryTransferStatus" AS ENUM ('DRAFT', 'IN_TRANSIT', 'PARTIAL_RECEIVED', 'RECEIVED', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryPreparationKind" AS ENUM ('SOCKET_FITTING', 'CHECK', 'PICKING');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryPreparationStatus" AS ENUM ('OPEN', 'DONE', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryIntegrationStatus" AS ENUM ('PENDING', 'PROCESSED', 'FAILED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryAccess" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" "InventoryRole" NOT NULL DEFAULT 'VIEWER',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryAccess_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryWarehouse" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "kind" "InventoryWarehouseKind" NOT NULL DEFAULT 'LOCAL',
    "countryCode" TEXT NOT NULL,
    "regionCode" TEXT,
    "address" TEXT NOT NULL DEFAULT '',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryWarehouse_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryWarehouseServiceRule" (
    "id" TEXT NOT NULL,
    "warehouseId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "regionCode" TEXT,
    "postalPrefix" TEXT,
    "priority" INTEGER NOT NULL DEFAULT 100,
    "leadTimeDays" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryWarehouseServiceRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventorySpot" (
    "id" TEXT NOT NULL,
    "warehouseId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventorySpot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryPallet" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "warehouseId" TEXT,
    "spotId" TEXT,
    "notes" TEXT NOT NULL DEFAULT '',
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryPallet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryFactory" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryFactory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryBatch" (
    "id" TEXT NOT NULL,
    "factoryId" TEXT NOT NULL,
    "batchNumber" TEXT NOT NULL,
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryBatch_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryFinish" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "details" JSONB,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryFinish_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryCatalogMapping" (
    "id" TEXT NOT NULL,
    "sourceSystem" TEXT NOT NULL,
    "sourceKind" TEXT NOT NULL,
    "sourceId" TEXT NOT NULL,
    "family" "BoothProductFamily",
    "finishId" TEXT,
    "recipeRevision" TEXT,
    "metadata" JSONB,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryCatalogMapping_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryUnit" (
    "id" TEXT NOT NULL,
    "family" "BoothProductFamily" NOT NULL,
    "finishId" TEXT NOT NULL,
    "voltage" "InventoryVoltage" NOT NULL DEFAULT 'UNKNOWN',
    "socketType" TEXT,
    "productVersion" TEXT,
    "batchId" TEXT,
    "factoryId" TEXT,
    "status" "BoothUnitStatus" NOT NULL DEFAULT 'PLANNED',
    "warehouseId" TEXT,
    "intendedWarehouseId" TEXT,
    "expectedReadyAt" TIMESTAMP(3),
    "receivedAt" TIMESTAMP(3),
    "packedCheckedAt" TIMESTAMP(3),
    "packedCheckedById" TEXT,
    "serialNumber" INTEGER,
    "serialCode" TEXT,
    "serialPrefix" TEXT,
    "serialIssuedAt" TIMESTAMP(3),
    "version" INTEGER NOT NULL DEFAULT 0,
    "blockedReason" TEXT,
    "dispatchedAt" TIMESTAMP(3),
    "retiredAt" TIMESTAMP(3),
    "sourceSystem" TEXT,
    "sourceId" TEXT,
    "metadata" JSONB,
    "notes" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryUnit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryPalletContent" (
    "id" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "palletId" TEXT NOT NULL,
    "packageKey" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryPalletContent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryDemand" (
    "id" TEXT NOT NULL,
    "sourceSystem" TEXT NOT NULL,
    "sourceId" TEXT NOT NULL,
    "kind" "InventoryDemandKind" NOT NULL,
    "state" "InventoryDemandState" NOT NULL DEFAULT 'OPEN',
    "dealId" TEXT,
    "quoteId" TEXT,
    "reference" TEXT,
    "customerName" TEXT,
    "countryCode" TEXT,
    "regionCode" TEXT,
    "postalCode" TEXT,
    "preferredWarehouseId" TEXT,
    "requiredAt" TIMESTAMP(3),
    "activeVariationKey" TEXT,
    "version" INTEGER NOT NULL DEFAULT 0,
    "sourceVersion" BIGINT NOT NULL DEFAULT 0,
    "reservationRequestedAt" TIMESTAMP(3),
    "reservationRequestedById" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryDemand_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryDemandLine" (
    "id" TEXT NOT NULL,
    "demandId" TEXT NOT NULL,
    "sourceLineId" TEXT NOT NULL,
    "family" "BoothProductFamily" NOT NULL,
    "finishId" TEXT,
    "voltage" "InventoryVoltage" NOT NULL DEFAULT 'UNKNOWN',
    "socketType" TEXT,
    "productVersion" TEXT,
    "quantity" INTEGER NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryDemandLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventorySuggestion" (
    "id" TEXT NOT NULL,
    "demandId" TEXT NOT NULL,
    "demandVersion" INTEGER NOT NULL,
    "items" JSONB NOT NULL,
    "shortages" JSONB,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3),

    CONSTRAINT "InventorySuggestion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryAllocation" (
    "id" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "demandLineId" TEXT NOT NULL,
    "slot" INTEGER NOT NULL DEFAULT 1,
    "kind" "InventoryAllocationKind" NOT NULL,
    "status" "InventoryAllocationStatus" NOT NULL DEFAULT 'ACTIVE',
    "reservedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3),
    "confirmedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "confirmedById" TEXT,
    "requestedById" TEXT,
    "protectedByOps" BOOLEAN NOT NULL DEFAULT false,
    "reason" TEXT,
    "releasedAt" TIMESTAMP(3),
    "releasedById" TEXT,
    "releaseReason" TEXT,
    "version" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventorySerialSequence" (
    "id" TEXT NOT NULL DEFAULT 'global',
    "nextNumber" INTEGER NOT NULL DEFAULT 40000,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventorySerialSequence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryTransfer" (
    "id" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "originWarehouseId" TEXT NOT NULL,
    "destinationWarehouseId" TEXT NOT NULL,
    "status" "InventoryTransferStatus" NOT NULL DEFAULT 'DRAFT',
    "expectedAt" TIMESTAMP(3),
    "dispatchedAt" TIMESTAMP(3),
    "receivedAt" TIMESTAMP(3),
    "createdById" TEXT,
    "dispatchedById" TEXT,
    "receivedById" TEXT,
    "notes" TEXT NOT NULL DEFAULT '',
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryTransferItem" (
    "id" TEXT NOT NULL,
    "transferId" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "contentId" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "receivedQuantity" INTEGER NOT NULL DEFAULT 0,
    "originWarehouseId" TEXT NOT NULL,
    "destinationWarehouseId" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3),
    "receivedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryTransferItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryPreparationTask" (
    "id" TEXT NOT NULL,
    "unitId" TEXT NOT NULL,
    "allocationId" TEXT,
    "kind" "InventoryPreparationKind" NOT NULL,
    "status" "InventoryPreparationStatus" NOT NULL DEFAULT 'OPEN',
    "socketType" TEXT,
    "notes" TEXT NOT NULL DEFAULT '',
    "completedAt" TIMESTAMP(3),
    "completedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryPreparationTask_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryAuditEvent" (
    "id" TEXT NOT NULL,
    "unitId" TEXT,
    "demandId" TEXT,
    "actorId" TEXT,
    "actorName" TEXT,
    "action" TEXT NOT NULL,
    "reason" TEXT,
    "before" JSONB,
    "after" JSONB,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryAuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryOperation" (
    "key" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "payloadHash" TEXT NOT NULL,
    "result" JSONB NOT NULL,
    "actorId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryOperation_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "InventoryIntegrationEvent" (
    "id" TEXT NOT NULL,
    "sourceSystem" TEXT NOT NULL,
    "sourceEventId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "actorUserId" TEXT,
    "payload" JSONB NOT NULL,
    "payloadHash" TEXT,
    "status" "InventoryIntegrationStatus" NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),

    CONSTRAINT "InventoryIntegrationEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryAccess_userId_role_key" ON "InventoryAccess"("userId", "role");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryWarehouse_code_key" ON "InventoryWarehouse"("code");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryWarehouse_kind_active_idx" ON "InventoryWarehouse"("kind", "active");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryWarehouseServiceRule_countryCode_active_priority_idx" ON "InventoryWarehouseServiceRule"("countryCode", "active", "priority");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryWarehouseServiceRule_warehouseId_idx" ON "InventoryWarehouseServiceRule"("warehouseId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventorySpot_warehouseId_code_key" ON "InventorySpot"("warehouseId", "code");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventorySpot_id_warehouseId_key" ON "InventorySpot"("id", "warehouseId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryPallet_code_key" ON "InventoryPallet"("code");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryPallet_warehouseId_idx" ON "InventoryPallet"("warehouseId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryPallet_spotId_warehouseId_idx" ON "InventoryPallet"("spotId", "warehouseId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryFactory_code_key" ON "InventoryFactory"("code");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryFactory_sourceSystem_sourceId_key" ON "InventoryFactory"("sourceSystem", "sourceId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryBatch_factoryId_batchNumber_key" ON "InventoryBatch"("factoryId", "batchNumber");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryBatch_sourceSystem_sourceId_key" ON "InventoryBatch"("sourceSystem", "sourceId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryBatch_id_factoryId_key" ON "InventoryBatch"("id", "factoryId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryFinish_code_key" ON "InventoryFinish"("code");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryCatalogMapping_finishId_idx" ON "InventoryCatalogMapping"("finishId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryCatalogMapping_sourceSystem_sourceKind_sourceId_key" ON "InventoryCatalogMapping"("sourceSystem", "sourceKind", "sourceId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryUnit_serialNumber_key" ON "InventoryUnit"("serialNumber");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryUnit_serialCode_key" ON "InventoryUnit"("serialCode");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_family_finishId_voltage_status_idx" ON "InventoryUnit"("family", "finishId", "voltage", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_warehouseId_status_idx" ON "InventoryUnit"("warehouseId", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_intendedWarehouseId_idx" ON "InventoryUnit"("intendedWarehouseId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_factoryId_idx" ON "InventoryUnit"("factoryId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryUnit_batchId_factoryId_idx" ON "InventoryUnit"("batchId", "factoryId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryUnit_sourceSystem_sourceId_key" ON "InventoryUnit"("sourceSystem", "sourceId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryPalletContent_palletId_idx" ON "InventoryPalletContent"("palletId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryPalletContent_unitId_packageKey_key" ON "InventoryPalletContent"("unitId", "packageKey");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryPalletContent_id_unitId_key" ON "InventoryPalletContent"("id", "unitId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemand_dealId_idx" ON "InventoryDemand"("dealId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemand_quoteId_idx" ON "InventoryDemand"("quoteId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemand_state_kind_idx" ON "InventoryDemand"("state", "kind");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemand_preferredWarehouseId_idx" ON "InventoryDemand"("preferredWarehouseId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryDemand_sourceSystem_sourceId_key" ON "InventoryDemand"("sourceSystem", "sourceId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryDemandLine_finishId_idx" ON "InventoryDemandLine"("finishId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryDemandLine_demandId_sourceLineId_key" ON "InventoryDemandLine"("demandId", "sourceLineId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventorySuggestion_demandId_createdAt_idx" ON "InventorySuggestion"("demandId", "createdAt");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAllocation_unitId_status_idx" ON "InventoryAllocation"("unitId", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAllocation_demandLineId_status_idx" ON "InventoryAllocation"("demandLineId", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAllocation_status_expiresAt_idx" ON "InventoryAllocation"("status", "expiresAt");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAllocation_confirmedById_idx" ON "InventoryAllocation"("confirmedById");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryAllocation_id_unitId_key" ON "InventoryAllocation"("id", "unitId");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryTransfer_reference_key" ON "InventoryTransfer"("reference");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransfer_originWarehouseId_status_idx" ON "InventoryTransfer"("originWarehouseId", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransfer_destinationWarehouseId_status_idx" ON "InventoryTransfer"("destinationWarehouseId", "status");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryTransfer_id_originWarehouseId_destinationWarehouse_key" ON "InventoryTransfer"("id", "originWarehouseId", "destinationWarehouseId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransferItem_transferId_idx" ON "InventoryTransferItem"("transferId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransferItem_unitId_idx" ON "InventoryTransferItem"("unitId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransferItem_contentId_unitId_idx" ON "InventoryTransferItem"("contentId", "unitId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransferItem_originWarehouseId_idx" ON "InventoryTransferItem"("originWarehouseId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryTransferItem_destinationWarehouseId_idx" ON "InventoryTransferItem"("destinationWarehouseId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryPreparationTask_unitId_status_idx" ON "InventoryPreparationTask"("unitId", "status");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryPreparationTask_allocationId_idx" ON "InventoryPreparationTask"("allocationId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAuditEvent_unitId_createdAt_idx" ON "InventoryAuditEvent"("unitId", "createdAt");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAuditEvent_demandId_createdAt_idx" ON "InventoryAuditEvent"("demandId", "createdAt");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryAuditEvent_actorId_idx" ON "InventoryAuditEvent"("actorId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "InventoryIntegrationEvent_status_createdAt_idx" ON "InventoryIntegrationEvent"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryIntegrationEvent_sourceSystem_sourceEventId_key" ON "InventoryIntegrationEvent"("sourceSystem", "sourceEventId");

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAccess" ADD CONSTRAINT "InventoryAccess_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryWarehouseServiceRule" ADD CONSTRAINT "InventoryWarehouseServiceRule_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventorySpot" ADD CONSTRAINT "InventorySpot_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPallet" ADD CONSTRAINT "InventoryPallet_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPallet" ADD CONSTRAINT "InventoryPallet_spotId_warehouseId_fkey" FOREIGN KEY ("spotId", "warehouseId") REFERENCES "InventorySpot"("id", "warehouseId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryBatch" ADD CONSTRAINT "InventoryBatch_factoryId_fkey" FOREIGN KEY ("factoryId") REFERENCES "InventoryFactory"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryCatalogMapping" ADD CONSTRAINT "InventoryCatalogMapping_finishId_fkey" FOREIGN KEY ("finishId") REFERENCES "InventoryFinish"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_finishId_fkey" FOREIGN KEY ("finishId") REFERENCES "InventoryFinish"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_batchId_factoryId_fkey" FOREIGN KEY ("batchId", "factoryId") REFERENCES "InventoryBatch"("id", "factoryId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_factoryId_fkey" FOREIGN KEY ("factoryId") REFERENCES "InventoryFactory"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_warehouseId_fkey" FOREIGN KEY ("warehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_intendedWarehouseId_fkey" FOREIGN KEY ("intendedWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPalletContent" ADD CONSTRAINT "InventoryPalletContent_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPalletContent" ADD CONSTRAINT "InventoryPalletContent_palletId_fkey" FOREIGN KEY ("palletId") REFERENCES "InventoryPallet"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryDemand" ADD CONSTRAINT "InventoryDemand_preferredWarehouseId_fkey" FOREIGN KEY ("preferredWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryDemandLine" ADD CONSTRAINT "InventoryDemandLine_demandId_fkey" FOREIGN KEY ("demandId") REFERENCES "InventoryDemand"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryDemandLine" ADD CONSTRAINT "InventoryDemandLine_finishId_fkey" FOREIGN KEY ("finishId") REFERENCES "InventoryFinish"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventorySuggestion" ADD CONSTRAINT "InventorySuggestion_demandId_fkey" FOREIGN KEY ("demandId") REFERENCES "InventoryDemand"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_demandLineId_fkey" FOREIGN KEY ("demandLineId") REFERENCES "InventoryDemandLine"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_confirmedById_fkey" FOREIGN KEY ("confirmedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransfer" ADD CONSTRAINT "InventoryTransfer_originWarehouseId_fkey" FOREIGN KEY ("originWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransfer" ADD CONSTRAINT "InventoryTransfer_destinationWarehouseId_fkey" FOREIGN KEY ("destinationWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_transferId_originWarehouseId_destina_fkey" FOREIGN KEY ("transferId", "originWarehouseId", "destinationWarehouseId") REFERENCES "InventoryTransfer"("id", "originWarehouseId", "destinationWarehouseId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_contentId_unitId_fkey" FOREIGN KEY ("contentId", "unitId") REFERENCES "InventoryPalletContent"("id", "unitId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_originWarehouseId_fkey" FOREIGN KEY ("originWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_destinationWarehouseId_fkey" FOREIGN KEY ("destinationWarehouseId") REFERENCES "InventoryWarehouse"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPreparationTask" ADD CONSTRAINT "InventoryPreparationTask_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryPreparationTask" ADD CONSTRAINT "InventoryPreparationTask_allocationId_unitId_fkey" FOREIGN KEY ("allocationId", "unitId") REFERENCES "InventoryAllocation"("id", "unitId") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAuditEvent" ADD CONSTRAINT "InventoryAuditEvent_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAuditEvent" ADD CONSTRAINT "InventoryAuditEvent_unitId_fkey" FOREIGN KEY ("unitId") REFERENCES "InventoryUnit"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AddForeignKey
DO $$ BEGIN
  ALTER TABLE "InventoryAuditEvent" ADD CONSTRAINT "InventoryAuditEvent_demandId_fkey" FOREIGN KEY ("demandId") REFERENCES "InventoryDemand"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


DO $$ BEGIN
  ALTER TABLE "InventoryWarehouseServiceRule" ADD CONSTRAINT "InventoryWarehouseServiceRule_nonnegative_check"
    CHECK ("leadTimeDays" >= 0 AND "priority" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryPallet" ADD CONSTRAINT "InventoryPallet_spot_warehouse_check"
    CHECK ("spotId" IS NULL OR "warehouseId" IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_batch_factory_check"
    CHECK ("batchId" IS NULL OR "factoryId" IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_serial_range_check"
    CHECK ("serialNumber" IS NULL OR "serialNumber" BETWEEN 0 AND 99999);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_version_nonnegative_check"
    CHECK ("version" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryPalletContent" ADD CONSTRAINT "InventoryPalletContent_positive_quantity_check"
    CHECK ("quantity" > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryDemand" ADD CONSTRAINT "InventoryDemand_versions_nonnegative_check"
    CHECK ("version" >= 0 AND "sourceVersion" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryDemandLine" ADD CONSTRAINT "InventoryDemandLine_quantity_check"
    CHECK ("quantity" >= 0 AND (NOT "active" OR "quantity" > 0));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_positive_slot_check"
    CHECK ("slot" > 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_hold_expiry_check"
    CHECK (("kind" = 'QUOTE_HOLD' AND "expiresAt" IS NOT NULL AND "expiresAt" > "reservedAt" AND "expiresAt" <= "reservedAt" + INTERVAL '7 days') OR ("kind" = 'COMMITTED' AND "expiresAt" IS NULL));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventorySerialSequence" ADD CONSTRAINT "InventorySerialSequence_global_check"
    CHECK ("id" = 'global' AND "nextNumber" BETWEEN 40000 AND 100000);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryTransfer" ADD CONSTRAINT "InventoryTransfer_different_warehouses_check"
    CHECK ("originWarehouseId" <> "destinationWarehouseId");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_receipt_quantity_check"
    CHECK ("quantity" > 0 AND "receivedQuantity" >= 0 AND "receivedQuantity" <= "quantity");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryTransferItem" ADD CONSTRAINT "InventoryTransferItem_complete_unit_quantity_check"
    CHECK ("contentId" IS NOT NULL OR "quantity" = 1);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryIntegrationEvent" ADD CONSTRAINT "InventoryIntegrationEvent_attempts_nonnegative_check"
    CHECK ("attempts" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- A proposal never owns stock. Only ACTIVE allocations consume capacity.
-- Expired rows must be marked EXPIRED within the serializable claim transaction;
-- a clock-dependent partial index is impossible and would be unsafe.
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryAllocation_one_active_unit"
  ON "InventoryAllocation" ("unitId") WHERE "status" = 'ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryAllocation_one_active_demand_slot"
  ON "InventoryAllocation" ("demandLineId", "slot") WHERE "status" = 'ACTIVE';

-- Prevent duplicate copies of the same package / complete unit in one manifest.
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryTransferItem_unique_package"
  ON "InventoryTransferItem" ("transferId", "contentId") WHERE "contentId" IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "InventoryTransferItem_unique_complete_unit"
  ON "InventoryTransferItem" ("transferId", "unitId") WHERE "contentId" IS NULL;

COMMIT;
