-- Assembly calendar / market-filtered lists: WHERE market IN (...) ORDER BY assemblyDate.
-- Apply: npx prisma db execute --file scripts/add-assembly-market-index.sql --schema prisma/schema.prisma

CREATE INDEX IF NOT EXISTS "Assembly_market_assemblyDate_idx"
  ON "Assembly" ("market", "assemblyDate");
