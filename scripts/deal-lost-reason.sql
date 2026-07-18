-- Lost reason on Deal when a quote is marked LOST — safe to run on production.
-- Apply: npx prisma db execute --file scripts/deal-lost-reason.sql --schema prisma/schema.prisma

DO $$ BEGIN
  CREATE TYPE "LostReason" AS ENUM (
    'PROJECT_CANCELLED',
    'CHOSE_COMPETITOR',
    'PRICE_TOO_HIGH',
    'NO_REPLY',
    'OTHER'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "lostReason" "LostReason";

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "lostReasonNote" TEXT NOT NULL DEFAULT '';
