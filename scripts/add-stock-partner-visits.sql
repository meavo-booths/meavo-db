-- Apply:
--   npx prisma db execute --file scripts/add-stock-partner-visits.sql --schema prisma/schema.prisma
-- Additive only: partner usage visit log for stock.meavo.app. Does not touch other apps' tables.

DO $$ BEGIN
  CREATE TYPE "StockPartnerVisitKind" AS ENUM (
    'LOGIN',
    'PAGE_VIEW'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "StockPartnerVisit" (
  "id" TEXT NOT NULL,
  "partnerId" TEXT NOT NULL,
  "kind" "StockPartnerVisitKind" NOT NULL,
  "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StockPartnerVisit_pkey" PRIMARY KEY ("id")
);

DO $$ BEGIN
  ALTER TABLE "StockPartnerVisit"
    ADD CONSTRAINT "StockPartnerVisit_partnerId_fkey"
    FOREIGN KEY ("partnerId") REFERENCES "StockPartner"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "StockPartnerVisit_partnerId_occurredAt_idx"
  ON "StockPartnerVisit"("partnerId", "occurredAt");
