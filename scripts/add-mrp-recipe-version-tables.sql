-- MRP recipe-version v2/v3 and electric v2 objects: additive, transactional,
-- idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-mrp-recipe-version-tables.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-mrp-recipe-version-tables.sql --schema prisma/schema.prisma
-- Required existing objects: MrpRecipeVersion, MrpRecipeVersionPanel,
-- MrpManufacturingBatch, MrpBatchUnit, MrpElectricModule, MrpBoothModel,
-- MrpWarehouse, User, enum MrpStockMovementType.
--
-- Declares in meavo-db what the MRP app created with its own build-time SQL
-- (meavo-mrp scripts/add-mrp-recipe-version-v2.sql, -v3.sql,
-- add-mrp-electric-v2.sql and the mrp_one_shot_script marker table of its data
-- scripts). Every object is written exactly as production had it on
-- 6 November 2026 (information_schema, pg_constraint, pg_indexes and pg_enum read
-- through _shared/tools/prod-read.mjs), including names, defaults and
-- ON DELETE / ON UPDATE actions. On production every statement is a no-op; the
-- staging branch has the same objects except the MrpElectricModule."updatedAt"
-- default, which production has and staging lacks. Fresh databases get everything.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "MrpRecipeVersionKind" AS ENUM ('recipe', 'documentation');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "MrpRecipeVersionColoursMode" AS ENUM ('all', 'any', 'specific');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AlterEnum: production order ends ..., inventory_count, bom_rework_adjustment, electric_consumption.
-- The value is not used in this transaction, so ADD VALUE is safe inside it.
ALTER TYPE "MrpStockMovementType" ADD VALUE IF NOT EXISTS 'electric_consumption';

-- AlterTable: MrpRecipeVersion (v2 + v3 metadata)
ALTER TABLE "MrpRecipeVersion"
  ADD COLUMN IF NOT EXISTS "kind" "MrpRecipeVersionKind" NOT NULL DEFAULT 'recipe',
  ADD COLUMN IF NOT EXISTS "description" TEXT,
  ADD COLUMN IF NOT EXISTS "reason" TEXT,
  ADD COLUMN IF NOT EXISTS "affectedColours" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "clientVisible" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "assemblyChangeRequired" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "sparePartsImpact" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "introducedOn" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "lockedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "stakeholdersBriefed" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "affectedColoursMode" "MrpRecipeVersionColoursMode" NOT NULL DEFAULT 'any';

CREATE INDEX IF NOT EXISTS "MrpRecipeVersion_boothModelId_introducedOn_idx"
  ON "MrpRecipeVersion"("boothModelId", "introducedOn");

-- AlterTable: other MRP tables
ALTER TABLE "MrpRecipeVersionPanel" ADD COLUMN IF NOT EXISTS "note" TEXT;

ALTER TABLE "MrpManufacturingBatch"
  ADD COLUMN IF NOT EXISTS "prefix" TEXT,
  ADD COLUMN IF NOT EXISTS "sequence" INTEGER;

CREATE INDEX IF NOT EXISTS "MrpManufacturingBatch_prefix_sequence_idx"
  ON "MrpManufacturingBatch"("prefix", "sequence");

ALTER TABLE "MrpBatchUnit" ADD COLUMN IF NOT EXISTS "electricDeductionPosted" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "MrpElectricModule" ADD COLUMN IF NOT EXISTS "boothModelId" TEXT;

CREATE INDEX IF NOT EXISTS "MrpElectricModule_boothModelId_idx"
  ON "MrpElectricModule"("boothModelId");

DO $$ BEGIN
  ALTER TABLE "MrpElectricModule" ADD CONSTRAINT "MrpElectricModule_boothModelId_fkey"
    FOREIGN KEY ("boothModelId") REFERENCES "MrpBoothModel"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Production has DEFAULT CURRENT_TIMESTAMP here; set it only where it is missing.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema() AND table_name = 'MrpElectricModule'
      AND column_name = 'updatedAt' AND column_default IS NULL
  ) THEN
    ALTER TABLE "MrpElectricModule" ALTER COLUMN "updatedAt" SET DEFAULT CURRENT_TIMESTAMP;
  END IF;
END $$;

-- CreateTable: MrpRecipeVersionScope
CREATE TABLE IF NOT EXISTS "MrpRecipeVersionScope" (
    "id" TEXT NOT NULL,
    "recipeVersionId" TEXT NOT NULL,
    "warehouseId" TEXT,
    "fromBatchId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fromBatchName" TEXT,

    CONSTRAINT "MrpRecipeVersionScope_pkey" PRIMARY KEY ("id")
);
ALTER TABLE "MrpRecipeVersionScope" ADD COLUMN IF NOT EXISTS "fromBatchName" TEXT;

CREATE INDEX IF NOT EXISTS "MrpRecipeVersionScope_recipeVersionId_idx"
  ON "MrpRecipeVersionScope"("recipeVersionId");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersionScope_fromBatchId_idx"
  ON "MrpRecipeVersionScope"("fromBatchId");

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionScope" ADD CONSTRAINT "MrpRecipeVersionScope_recipeVersionId_fkey"
    FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionScope" ADD CONSTRAINT "MrpRecipeVersionScope_warehouseId_fkey"
    FOREIGN KEY ("warehouseId") REFERENCES "MrpWarehouse"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionScope" ADD CONSTRAINT "MrpRecipeVersionScope_fromBatchId_fkey"
    FOREIGN KEY ("fromBatchId") REFERENCES "MrpManufacturingBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable: MrpRecipeVersionAmendment
CREATE TABLE IF NOT EXISTS "MrpRecipeVersionAmendment" (
    "id" TEXT NOT NULL,
    "recipeVersionId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "reason" TEXT NOT NULL,
    "summary" TEXT,

    CONSTRAINT "MrpRecipeVersionAmendment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "MrpRecipeVersionAmendment_recipeVersionId_idx"
  ON "MrpRecipeVersionAmendment"("recipeVersionId");

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionAmendment" ADD CONSTRAINT "MrpRecipeVersionAmendment_recipeVersionId_fkey"
    FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionAmendment" ADD CONSTRAINT "MrpRecipeVersionAmendment_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable: MrpRecipeVersionDocumentLink
CREATE TABLE IF NOT EXISTS "MrpRecipeVersionDocumentLink" (
    "id" TEXT NOT NULL,
    "recipeVersionId" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "label" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MrpRecipeVersionDocumentLink_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "MrpRecipeVersionDocumentLink_recipeVersionId_idx"
  ON "MrpRecipeVersionDocumentLink"("recipeVersionId");

DO $$ BEGIN
  ALTER TABLE "MrpRecipeVersionDocumentLink" ADD CONSTRAINT "MrpRecipeVersionDocumentLink_recipeVersionId_fkey"
    FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable: mrp_one_shot_script (marker rows of MRP one-off data scripts)
CREATE TABLE IF NOT EXISTS "mrp_one_shot_script" (
    "name" TEXT NOT NULL,
    "ran_at" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "mrp_one_shot_script_pkey" PRIMARY KEY ("name")
);

COMMIT;
