-- Additive: ensure Product.publicName exists, then copy name into empty values.
-- Apply: npx prisma db execute --file scripts/product-public-name-backfill.sql --schema prisma/schema.prisma
-- Prefer this over db:push when the local schema may lag other apps' tables.

ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "publicName" TEXT NOT NULL DEFAULT '';

UPDATE "Product" SET "publicName" = name WHERE "publicName" = '';
