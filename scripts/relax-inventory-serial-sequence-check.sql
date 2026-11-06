-- Let InventorySerialSequence hold the real next booth number (0.104.0).
--
-- Booth numbers are one five-digit series (cross-app review, 5 November 2026):
-- planning-sheet ids run from 5515, and the numbers Inventory issues continue after
-- the highest id in planning, MRP or Inventory, never below 10000. The V1 check
-- (add-inventory-v1.sql) only admitted 40000 to 100000, so Inventory kept the row at
-- 40000 as a lock and carried the series in the booths. This widens the check to
-- 10000 to 100000 (100000 stays the "series exhausted" value) and lowers the column
-- default to match. Every value the old check admitted is still valid.
--
-- Safe to run repeatedly.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public."InventorySerialSequence"'::regclass
      AND conname = 'InventorySerialSequence_global_check'
      AND pg_get_constraintdef(oid) LIKE '%("nextNumber" >= 10000)%'
  ) THEN
    ALTER TABLE "InventorySerialSequence" DROP CONSTRAINT IF EXISTS "InventorySerialSequence_global_check";
    ALTER TABLE "InventorySerialSequence" ADD CONSTRAINT "InventorySerialSequence_global_check"
      CHECK ("id" = 'global' AND "nextNumber" BETWEEN 10000 AND 100000);
  END IF;
END $$;

ALTER TABLE "InventorySerialSequence" ALTER COLUMN "nextNumber" SET DEFAULT 10000;

COMMIT;
