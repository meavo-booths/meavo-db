-- Apply:
--   npx prisma db execute --file scripts/add-stock-partner-us-cities.sql --schema prisma/schema.prisma
-- Additive only: US city location recipes for stock.meavo.app partner portals.

ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_NY';
ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_CHI';
ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_BOS';
ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_HOU';
ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_SF';
ALTER TYPE "StockPartnerLocation" ADD VALUE IF NOT EXISTS 'US_LA';
