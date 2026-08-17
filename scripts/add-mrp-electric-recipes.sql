-- MRP electric module + assembly recipes (parallel to packing ElementBOM).
-- Apply: npx prisma db execute --file scripts/add-mrp-electric-recipes.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "MrpElectricModule" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "partCode" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "notes" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MrpElectricModule_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricModule_code_key" ON "MrpElectricModule"("code");

-- Existing installs created the table before partCode existed.
ALTER TABLE "MrpElectricModule" ADD COLUMN IF NOT EXISTS "partCode" TEXT;
UPDATE "MrpElectricModule"
SET "partCode" = "code"
WHERE "partCode" IS NULL OR btrim("partCode") = '';
CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricModule_partCode_key" ON "MrpElectricModule"("partCode");
ALTER TABLE "MrpElectricModule" ALTER COLUMN "partCode" SET NOT NULL;

CREATE TABLE IF NOT EXISTS "MrpElectricModuleLine" (
    "id" TEXT NOT NULL,
    "moduleId" TEXT NOT NULL,
    "materialId" TEXT NOT NULL,
    "market" TEXT,
    "quantity" DECIMAL(18,4) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MrpElectricModuleLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricModuleLine_moduleId_market_materialId_key"
  ON "MrpElectricModuleLine"("moduleId", "market", "materialId");
CREATE INDEX IF NOT EXISTS "MrpElectricModuleLine_materialId_idx"
  ON "MrpElectricModuleLine"("materialId");

CREATE TABLE IF NOT EXISTS "MrpElectricAssembly" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "boothModelId" TEXT NOT NULL,
    "kind" TEXT,
    "notes" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MrpElectricAssembly_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricAssembly_code_key" ON "MrpElectricAssembly"("code");
CREATE INDEX IF NOT EXISTS "MrpElectricAssembly_boothModelId_idx" ON "MrpElectricAssembly"("boothModelId");

CREATE TABLE IF NOT EXISTS "MrpElectricAssemblyLine" (
    "id" TEXT NOT NULL,
    "assemblyId" TEXT NOT NULL,
    "moduleId" TEXT NOT NULL,
    "quantity" DECIMAL(18,4) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MrpElectricAssemblyLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpElectricAssemblyLine_assemblyId_moduleId_key"
  ON "MrpElectricAssemblyLine"("assemblyId", "moduleId");
CREATE INDEX IF NOT EXISTS "MrpElectricAssemblyLine_moduleId_idx"
  ON "MrpElectricAssemblyLine"("moduleId");

DO $$ BEGIN
  ALTER TABLE "MrpElectricModuleLine"
    ADD CONSTRAINT "MrpElectricModuleLine_moduleId_fkey"
    FOREIGN KEY ("moduleId") REFERENCES "MrpElectricModule"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricModuleLine"
    ADD CONSTRAINT "MrpElectricModuleLine_materialId_fkey"
    FOREIGN KEY ("materialId") REFERENCES "MrpMaterial"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssembly"
    ADD CONSTRAINT "MrpElectricAssembly_boothModelId_fkey"
    FOREIGN KEY ("boothModelId") REFERENCES "MrpBoothModel"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssemblyLine"
    ADD CONSTRAINT "MrpElectricAssemblyLine_assemblyId_fkey"
    FOREIGN KEY ("assemblyId") REFERENCES "MrpElectricAssembly"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpElectricAssemblyLine"
    ADD CONSTRAINT "MrpElectricAssemblyLine_moduleId_fkey"
    FOREIGN KEY ("moduleId") REFERENCES "MrpElectricModule"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
