-- Apply:
--   npx prisma db execute --file scripts/add-stock-partner.sql --schema prisma/schema.prisma
-- Additive only: partner portals for stock.meavo.app. Does not touch other apps' tables.

DO $$ BEGIN
  CREATE TYPE "StockPartnerLocation" AS ENUM (
    'UK',
    'FR',
    'DE',
    'ES',
    'US_EAST',
    'US_WEST',
    'OTHER_EU'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "StockPartner" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "slug" TEXT NOT NULL,
  "username" TEXT NOT NULL,
  "passwordHash" TEXT NOT NULL,
  "location" "StockPartnerLocation" NOT NULL,
  "note" TEXT,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdById" TEXT NOT NULL,
  "lastLoginAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "StockPartner_pkey" PRIMARY KEY ("id")
);

DO $$ BEGIN
  ALTER TABLE "StockPartner"
    ADD CONSTRAINT "StockPartner_createdById_fkey"
    FOREIGN KEY ("createdById") REFERENCES "User"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "StockPartner_slug_key" ON "StockPartner"("slug");
CREATE UNIQUE INDEX IF NOT EXISTS "StockPartner_username_key" ON "StockPartner"("username");
CREATE INDEX IF NOT EXISTS "StockPartner_isActive_idx" ON "StockPartner"("isActive");
CREATE INDEX IF NOT EXISTS "StockPartner_location_idx" ON "StockPartner"("location");
CREATE INDEX IF NOT EXISTS "StockPartner_createdById_idx" ON "StockPartner"("createdById");
