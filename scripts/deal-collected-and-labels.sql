-- Sales: amount collected on deals, and reusable deal labels.
-- Apply: npx prisma db execute --file scripts/deal-collected-and-labels.sql --schema prisma/schema.prisma
-- Apply this script instead of db push: the CHECK constraint is not expressed
-- in Prisma. This is additive and safe to rerun after a successful application.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "Deal" ADD COLUMN IF NOT EXISTS "amountCollected" DECIMAL(12,2);

CREATE TABLE IF NOT EXISTS "DealLabel" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "normalizedName" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "DealLabel_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "DealLabelAssignment" (
  "dealId" TEXT NOT NULL,
  "labelId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "DealLabelAssignment_pkey" PRIMARY KEY ("dealId", "labelId")
);

CREATE UNIQUE INDEX IF NOT EXISTS "DealLabel_normalizedName_key"
  ON "DealLabel"("normalizedName");
CREATE INDEX IF NOT EXISTS "DealLabelAssignment_labelId_idx"
  ON "DealLabelAssignment"("labelId");

DO $$ BEGIN
  ALTER TABLE "DealLabelAssignment" ADD CONSTRAINT "DealLabelAssignment_dealId_fkey"
    FOREIGN KEY ("dealId") REFERENCES "Deal"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "DealLabelAssignment" ADD CONSTRAINT "DealLabelAssignment_labelId_fkey"
    FOREIGN KEY ("labelId") REFERENCES "DealLabel"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "DealLabel" ADD CONSTRAINT "DealLabel_normalizedName_check"
    CHECK ("normalizedName" <> '' AND "normalizedName" = lower(btrim("name")));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
