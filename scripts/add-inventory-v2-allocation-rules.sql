-- Inventory V2 allocation rules: additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: npx prisma db execute --file scripts/add-inventory-v2-allocation-rules.sql --schema prisma/schema.prisma
-- Required existing objects: scripts/add-inventory-v1.sql, PaymentStatus, PaymentTerms, DeliveryType.
-- Adds automatic (pending) allocations, won-deal holds, the payment gate and
-- delivery mirrors on demand, and the market -> country mapping column.
-- Enum values added in this transaction cannot be used as literals until it
-- commits, so the CHECK constraints compare ::text. Existing allocations keep
-- their confirmedAt and become origin MANUAL; nothing is pending retroactively.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- AlterEnum
ALTER TYPE "InventoryAllocationKind" ADD VALUE IF NOT EXISTS 'DEAL_HOLD';

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "InventoryAllocationOrigin" AS ENUM ('MANUAL', 'AUTOMATIC');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AlterTable: pending allocations have no confirmedAt; MANUAL rows must have one.
ALTER TABLE "InventoryAllocation"
  ADD COLUMN IF NOT EXISTS "origin" "InventoryAllocationOrigin" NOT NULL DEFAULT 'MANUAL';
ALTER TABLE "InventoryAllocation" ALTER COLUMN "confirmedAt" DROP DEFAULT;
ALTER TABLE "InventoryAllocation" ALTER COLUMN "confirmedAt" DROP NOT NULL;

DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_origin_confirmed_check"
    CHECK ("origin"::text = 'AUTOMATIC' OR "confirmedAt" IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Hold expiry now covers quote holds and won-deal holds; committed rows never expire.
ALTER TABLE "InventoryAllocation" DROP CONSTRAINT IF EXISTS "InventoryAllocation_hold_expiry_check";
DO $$ BEGIN
  ALTER TABLE "InventoryAllocation" ADD CONSTRAINT "InventoryAllocation_hold_expiry_v2_check"
    CHECK (
      ("kind"::text IN ('QUOTE_HOLD', 'DEAL_HOLD')
        AND "expiresAt" IS NOT NULL
        AND "expiresAt" > "reservedAt"
        AND "expiresAt" <= "reservedAt" + INTERVAL '7 days')
      OR ("kind"::text = 'COMMITTED' AND "expiresAt" IS NULL)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "InventoryAllocation_status_confirmedAt_idx"
  ON "InventoryAllocation"("status", "confirmedAt");

-- AlterTable: payment gate and delivery mirrors on demand.
ALTER TABLE "InventoryDemand"
  ADD COLUMN IF NOT EXISTS "paymentCleared" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "paymentStatus" "PaymentStatus",
  ADD COLUMN IF NOT EXISTS "paymentTerms" "PaymentTerms",
  ADD COLUMN IF NOT EXISTS "paymentCheckedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "deliveryType" "DeliveryType",
  ADD COLUMN IF NOT EXISTS "deliveryAddress" TEXT,
  ADD COLUMN IF NOT EXISTS "shipDirect" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "InventoryDemand_state_paymentCleared_idx"
  ON "InventoryDemand"("state", "paymentCleared");

-- AlterTable: reviewed Sales market -> delivery country mapping (sourceKind 'market').
ALTER TABLE "InventoryCatalogMapping"
  ADD COLUMN IF NOT EXISTS "countryCode" TEXT;

DO $$ BEGIN
  ALTER TABLE "InventoryCatalogMapping" ADD CONSTRAINT "InventoryCatalogMapping_country_shape_check"
    CHECK ("countryCode" IS NULL OR "countryCode" ~ '^[A-Z]{2}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
