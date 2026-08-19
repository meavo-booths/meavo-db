-- Trade description on products for the sales app (Sales-owned; blank = retail description).
-- Apply: npx prisma db execute --file scripts/product-trade-description.sql --schema prisma/schema.prisma

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "tradeDescription" TEXT NOT NULL DEFAULT '';
