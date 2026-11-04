-- Sales BoothUnit inventory link: additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: npx prisma db execute --file scripts/add-booth-unit-inventory-link.sql --schema prisma/schema.prisma
-- Required existing object: BoothUnit (Sales-owned).
-- Three nullable columns that only the Inventory service writes: the allocated
-- physical InventoryUnit, its serial, and when status/location were last synced.
-- No FK to InventoryUnit on purpose: the Sales table stays usable without the
-- Inventory tables. Rollback keeps the columns; Inventory simply stops writing.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- AlterTable
ALTER TABLE "BoothUnit"
  ADD COLUMN IF NOT EXISTS "inventoryUnitId" TEXT,
  ADD COLUMN IF NOT EXISTS "serialCode" TEXT,
  ADD COLUMN IF NOT EXISTS "inventorySyncedAt" TIMESTAMP(3);

-- CreateIndex: one Sales demand row per physical booth.
CREATE UNIQUE INDEX IF NOT EXISTS "BoothUnit_inventoryUnitId_key" ON "BoothUnit"("inventoryUnitId");

COMMIT;
