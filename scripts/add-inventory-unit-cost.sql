-- Inventory booth cost: additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: npx prisma db execute --file scripts/add-inventory-unit-cost.sql --schema prisma/schema.prisma
-- Required existing object: InventoryUnit (scripts/add-inventory-v1.sql).
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- Existing units remain unvalued; this script does not invent or backfill costs.
-- No production application is authorized by this file.
BEGIN;

ALTER TABLE "InventoryUnit"
  ADD COLUMN IF NOT EXISTS "costAmount" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "costCurrency" TEXT;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_cost_pair_check"
    CHECK (("costAmount" IS NULL) = ("costCurrency" IS NULL));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_cost_nonnegative_check"
    CHECK ("costAmount" IS NULL OR
      ("costAmount" >= 0 AND "costAmount" <> 'NaN'::numeric));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "InventoryUnit" ADD CONSTRAINT "InventoryUnit_cost_currency_check"
    CHECK ("costCurrency" IS NULL OR "costCurrency" ~ '^[A-Z]{3}$');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
