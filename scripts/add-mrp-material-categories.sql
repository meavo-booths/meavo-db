-- MRP material category taxonomy (two-level tree + nullable MrpMaterial.categoryId).
-- Apply: npx prisma db execute --file scripts/add-mrp-material-categories.sql --schema prisma/schema.prisma

CREATE TABLE IF NOT EXISTS "MrpMaterialCategory" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "parentId" TEXT,
    CONSTRAINT "MrpMaterialCategory_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "MrpMaterialCategory_code_key" ON "MrpMaterialCategory"("code");
CREATE INDEX IF NOT EXISTS "MrpMaterialCategory_parentId_idx" ON "MrpMaterialCategory"("parentId");
CREATE INDEX IF NOT EXISTS "MrpMaterialCategory_isActive_sortOrder_idx" ON "MrpMaterialCategory"("isActive", "sortOrder");

ALTER TABLE "MrpMaterial" ADD COLUMN IF NOT EXISTS "categoryId" TEXT;

CREATE INDEX IF NOT EXISTS "MrpMaterial_categoryId_idx" ON "MrpMaterial"("categoryId");
CREATE INDEX IF NOT EXISTS "MrpMaterial_isActive_categoryId_idx" ON "MrpMaterial"("isActive", "categoryId");

DO $$ BEGIN
  ALTER TABLE "MrpMaterialCategory"
    ADD CONSTRAINT "MrpMaterialCategory_parentId_fkey"
    FOREIGN KEY ("parentId") REFERENCES "MrpMaterialCategory"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "MrpMaterial"
    ADD CONSTRAINT "MrpMaterial_categoryId_fkey"
    FOREIGN KEY ("categoryId") REFERENCES "MrpMaterialCategory"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
