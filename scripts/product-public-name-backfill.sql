-- Copy Product.name into publicName for rows that still have the empty default.
-- Apply after db:push adds the column:
--   npx prisma db execute --file scripts/product-public-name-backfill.sql --schema prisma/schema.prisma

UPDATE "Product" SET "publicName" = name WHERE "publicName" = '';
