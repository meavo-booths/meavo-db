-- Deal type (Retail/Trade), product trade pricing/naming, and the Showroom
-- client label for the sales app; ProductAvailability becomes market-only.
-- Additive except for the ProductAvailability primary-key move, which dedupes
-- rows to one per (productId, market) first. Idempotent.
-- Apply: npx prisma db execute --file scripts/sales-deal-type-trade-pricing.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "DealType" AS ENUM ('RETAIL', 'TRADE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "dealType" "DealType" NOT NULL DEFAULT 'RETAIL';

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "tradeName" TEXT NOT NULL DEFAULT '';

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "tradePrice" DECIMAL(12,2);

ALTER TABLE "Client"
  ADD COLUMN IF NOT EXISTS "isShowroom" BOOLEAN NOT NULL DEFAULT false;

-- ProductAvailability drops the client-type dimension: keep one row per
-- (productId, market), move the PK off clientType, and retire the column.
DELETE FROM "ProductAvailability" a
USING "ProductAvailability" b
WHERE a."productId" = b."productId"
  AND a."market" = b."market"
  AND a."clientType" > b."clientType";

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ProductAvailability_pkey'
      AND conrelid = '"ProductAvailability"'::regclass
      AND array_length(conkey, 1) = 3
  ) THEN
    ALTER TABLE "ProductAvailability" DROP CONSTRAINT "ProductAvailability_pkey";
    ALTER TABLE "ProductAvailability"
      ADD CONSTRAINT "ProductAvailability_pkey" PRIMARY KEY ("productId", "market");
  END IF;
END $$;

ALTER TABLE "ProductAvailability" ALTER COLUMN "clientType" DROP NOT NULL;

UPDATE "ProductAvailability" SET "clientType" = NULL WHERE "clientType" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "ProductAvailability_market_idx"
  ON "ProductAvailability"("market");

DROP INDEX IF EXISTS "ProductAvailability_market_clientType_idx";
