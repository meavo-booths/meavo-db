-- Soft delete on Deal for the sales app — safe to run on production.
-- Apply: npx prisma db execute --file scripts/deal-soft-delete.sql --schema prisma/schema.prisma

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMP(3);

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "deletedByUserId" TEXT;

CREATE INDEX IF NOT EXISTS "Deal_deletedAt_idx" ON "Deal"("deletedAt");
