-- Recipe versioning (idempotent). Apply before using /recipes version module.

DO $$ BEGIN
  CREATE TYPE "MrpRecipeVersionStatus" AS ENUM ('draft', 'ready', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "MrpRecipeVersionPanelChangeType" AS ENUM ('unchanged', 'recipe_changed', 'added', 'removed', 'renamed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "MrpRecipeVersionElectricParityMode" AS ENUM ('same_as_source', 'different');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "MrpElementBomLine" ADD COLUMN IF NOT EXISTS "recipeVersionId" TEXT;
ALTER TABLE "MrpManufacturingBatch" ADD COLUMN IF NOT EXISTS "recipeVersionId" TEXT;
ALTER TABLE "MrpManufacturingBatch" ADD COLUMN IF NOT EXISTS "sheetRecipeVersion" TEXT;

CREATE TABLE IF NOT EXISTS "MrpRecipeVersion" (
  "id" TEXT NOT NULL,
  "boothModelId" TEXT NOT NULL,
  "label" TEXT NOT NULL,
  "status" "MrpRecipeVersionStatus" NOT NULL DEFAULT 'draft',
  "notes" TEXT,
  "isDefault" BOOLEAN NOT NULL DEFAULT false,
  "sourceVersionId" TEXT,
  "createdById" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "MrpRecipeVersion_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "MrpRecipeVersionPanel" (
  "id" TEXT NOT NULL,
  "recipeVersionId" TEXT NOT NULL,
  "changeType" "MrpRecipeVersionPanelChangeType" NOT NULL DEFAULT 'unchanged',
  "boothElementId" TEXT,
  "sourcePanelId" TEXT,
  "sheetHeader" TEXT NOT NULL,
  "simpleName" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "recipeCopiedFromSource" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MrpRecipeVersionPanel_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "MrpRecipeVersionElectric" (
  "id" TEXT NOT NULL,
  "recipeVersionId" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "parityMode" "MrpRecipeVersionElectricParityMode" NOT NULL,
  "sourceAssemblyId" TEXT,
  "moduleSnapshot" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MrpRecipeVersionElectric_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "MrpRecipeVersionBatchLink" (
  "id" TEXT NOT NULL,
  "recipeVersionId" TEXT NOT NULL,
  "manufacturingBatchId" TEXT,
  "batchLabel" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MrpRecipeVersionBatchLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpRecipeVersion_boothModelId_label_key" ON "MrpRecipeVersion"("boothModelId", "label");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersion_boothModelId_status_idx" ON "MrpRecipeVersion"("boothModelId", "status");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersion_boothModelId_isDefault_idx" ON "MrpRecipeVersion"("boothModelId", "isDefault");

CREATE UNIQUE INDEX IF NOT EXISTS "MrpRecipeVersionPanel_recipeVersionId_sheetHeader_key" ON "MrpRecipeVersionPanel"("recipeVersionId", "sheetHeader");
CREATE UNIQUE INDEX IF NOT EXISTS "MrpRecipeVersionPanel_recipeVersionId_simpleName_key" ON "MrpRecipeVersionPanel"("recipeVersionId", "simpleName");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersionPanel_boothElementId_idx" ON "MrpRecipeVersionPanel"("boothElementId");

CREATE UNIQUE INDEX IF NOT EXISTS "MrpRecipeVersionElectric_recipeVersionId_kind_key" ON "MrpRecipeVersionElectric"("recipeVersionId", "kind");

CREATE INDEX IF NOT EXISTS "MrpRecipeVersionBatchLink_recipeVersionId_idx" ON "MrpRecipeVersionBatchLink"("recipeVersionId");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersionBatchLink_manufacturingBatchId_idx" ON "MrpRecipeVersionBatchLink"("manufacturingBatchId");
CREATE INDEX IF NOT EXISTS "MrpRecipeVersionBatchLink_batchLabel_idx" ON "MrpRecipeVersionBatchLink"("batchLabel");

DROP INDEX IF EXISTS "MrpElementBomLine_boothElementId_colour_market_materialId_key";
CREATE UNIQUE INDEX IF NOT EXISTS "MrpElementBomLine_recipeVersionId_boothElementId_colour_market_materialId_key"
  ON "MrpElementBomLine"("recipeVersionId", "boothElementId", "colour", "market", "materialId");
CREATE INDEX IF NOT EXISTS "MrpElementBomLine_recipeVersionId_idx" ON "MrpElementBomLine"("recipeVersionId");

ALTER TABLE "MrpElementBomLine" DROP CONSTRAINT IF EXISTS "MrpElementBomLine_recipeVersionId_fkey";
ALTER TABLE "MrpElementBomLine" ADD CONSTRAINT "MrpElementBomLine_recipeVersionId_fkey"
  FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MrpManufacturingBatch" DROP CONSTRAINT IF EXISTS "MrpManufacturingBatch_recipeVersionId_fkey";
ALTER TABLE "MrpManufacturingBatch" ADD CONSTRAINT "MrpManufacturingBatch_recipeVersionId_fkey"
  FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersion" DROP CONSTRAINT IF EXISTS "MrpRecipeVersion_boothModelId_fkey";
ALTER TABLE "MrpRecipeVersion" ADD CONSTRAINT "MrpRecipeVersion_boothModelId_fkey"
  FOREIGN KEY ("boothModelId") REFERENCES "MrpBoothModel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersion" DROP CONSTRAINT IF EXISTS "MrpRecipeVersion_sourceVersionId_fkey";
ALTER TABLE "MrpRecipeVersion" ADD CONSTRAINT "MrpRecipeVersion_sourceVersionId_fkey"
  FOREIGN KEY ("sourceVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersion" DROP CONSTRAINT IF EXISTS "MrpRecipeVersion_createdById_fkey";
ALTER TABLE "MrpRecipeVersion" ADD CONSTRAINT "MrpRecipeVersion_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionPanel" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionPanel_recipeVersionId_fkey";
ALTER TABLE "MrpRecipeVersionPanel" ADD CONSTRAINT "MrpRecipeVersionPanel_recipeVersionId_fkey"
  FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionPanel" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionPanel_boothElementId_fkey";
ALTER TABLE "MrpRecipeVersionPanel" ADD CONSTRAINT "MrpRecipeVersionPanel_boothElementId_fkey"
  FOREIGN KEY ("boothElementId") REFERENCES "MrpBoothElement"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionPanel" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionPanel_sourcePanelId_fkey";
ALTER TABLE "MrpRecipeVersionPanel" ADD CONSTRAINT "MrpRecipeVersionPanel_sourcePanelId_fkey"
  FOREIGN KEY ("sourcePanelId") REFERENCES "MrpRecipeVersionPanel"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionElectric" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionElectric_recipeVersionId_fkey";
ALTER TABLE "MrpRecipeVersionElectric" ADD CONSTRAINT "MrpRecipeVersionElectric_recipeVersionId_fkey"
  FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionElectric" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionElectric_sourceAssemblyId_fkey";
ALTER TABLE "MrpRecipeVersionElectric" ADD CONSTRAINT "MrpRecipeVersionElectric_sourceAssemblyId_fkey"
  FOREIGN KEY ("sourceAssemblyId") REFERENCES "MrpElectricAssembly"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionBatchLink" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionBatchLink_recipeVersionId_fkey";
ALTER TABLE "MrpRecipeVersionBatchLink" ADD CONSTRAINT "MrpRecipeVersionBatchLink_recipeVersionId_fkey"
  FOREIGN KEY ("recipeVersionId") REFERENCES "MrpRecipeVersion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MrpRecipeVersionBatchLink" DROP CONSTRAINT IF EXISTS "MrpRecipeVersionBatchLink_manufacturingBatchId_fkey";
ALTER TABLE "MrpRecipeVersionBatchLink" ADD CONSTRAINT "MrpRecipeVersionBatchLink_manufacturingBatchId_fkey"
  FOREIGN KEY ("manufacturingBatchId") REFERENCES "MrpManufacturingBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
