-- Product family metadata (image, dimensions, category) for sales quotes/PDFs.
-- Apply: npx prisma db execute --file scripts/add-product-family-info.sql

DO $$ BEGIN
  CREATE TYPE "ProductFamilyCategory" AS ENUM (
    'PHONE_BOOTH',
    'ADD_ON',
    'SERVICE'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS "ProductFamilyInfo" (
  "id" TEXT NOT NULL,
  "kind" "ProductKind" NOT NULL,
  "boothFamily" "BoothProductFamily",
  "addOnFamily" "AddOnProductFamily",
  "displayName" TEXT NOT NULL,
  "category" "ProductFamilyCategory" NOT NULL,
  "imageUrl" TEXT,
  "widthCm" DECIMAL(6,1),
  "depthCm" DECIMAL(6,1),
  "heightCm" DECIMAL(6,1),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ProductFamilyInfo_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ProductFamilyInfo_boothFamily_key"
  ON "ProductFamilyInfo"("boothFamily");

CREATE UNIQUE INDEX IF NOT EXISTS "ProductFamilyInfo_addOnFamily_key"
  ON "ProductFamilyInfo"("addOnFamily");

CREATE INDEX IF NOT EXISTS "ProductFamilyInfo_kind_idx"
  ON "ProductFamilyInfo"("kind");

CREATE INDEX IF NOT EXISTS "ProductFamilyInfo_category_idx"
  ON "ProductFamilyInfo"("category");
