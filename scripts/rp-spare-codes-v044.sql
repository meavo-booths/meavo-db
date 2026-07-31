-- RP spare catalogue: explicit RP Code plus MRP Material Code.
--
-- Apply after reviewing:
--   npx prisma db execute --schema prisma/schema.prisma \
--     --file scripts/rp-spare-codes-v044.sql
--
-- Existing values are preserved when `code` is renamed to `rp_code`.
-- The RP admin CSV will replace legacy 4-digit values with R### codes.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'rp_spare_parts'
      AND column_name = 'code'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'rp_spare_parts'
      AND column_name = 'rp_code'
  ) THEN
    ALTER TABLE "rp_spare_parts" RENAME COLUMN "code" TO "rp_code";
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'rp_spare_parts_code_key'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'rp_spare_parts_rp_code_key'
  ) THEN
    ALTER TABLE "rp_spare_parts"
      RENAME CONSTRAINT "rp_spare_parts_code_key"
      TO "rp_spare_parts_rp_code_key";
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.rp_spare_parts_code_key') IS NOT NULL
     AND to_regclass('public.rp_spare_parts_rp_code_key') IS NULL THEN
    ALTER INDEX "rp_spare_parts_code_key"
      RENAME TO "rp_spare_parts_rp_code_key";
  END IF;
END $$;

ALTER TABLE "rp_spare_parts"
  ADD COLUMN IF NOT EXISTS "material_code" TEXT;

CREATE INDEX IF NOT EXISTS "rp_spare_parts_material_code_idx"
  ON "rp_spare_parts"("material_code");
