-- Partner resource categories + per-image captions — safe to run on production.
-- Apply: npx prisma db execute --file scripts/add-resource-categories.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "ResourceCategoryKind" AS ENUM ('DELIVERY', 'ASSEMBLY', 'ELECTRICAL', 'REPAIRS');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "ResourceCategory" (
  "resourceId" TEXT NOT NULL,
  "category" "ResourceCategoryKind" NOT NULL,
  CONSTRAINT "ResourceCategory_pkey" PRIMARY KEY ("resourceId", "category")
);

DO $$ BEGIN
  ALTER TABLE "ResourceCategory"
    ADD CONSTRAINT "ResourceCategory_resourceId_fkey"
    FOREIGN KEY ("resourceId") REFERENCES "Resource"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "ResourceFile" ADD COLUMN IF NOT EXISTS "caption" TEXT NOT NULL DEFAULT '';
