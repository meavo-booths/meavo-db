-- Quote variations: link sibling Deal rows and a superseded lost reason.
--
-- Apply:
--   npx prisma db execute --file scripts/deal_quote_variations.sql --schema prisma/schema.prisma

ALTER TYPE "LostReason" ADD VALUE IF NOT EXISTS 'SUPERSEDED_BY_VARIATION';

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "canonicalQuoteId" TEXT;

DO $$ BEGIN
  ALTER TABLE "Deal"
    ADD CONSTRAINT "Deal_canonicalQuoteId_fkey"
    FOREIGN KEY ("canonicalQuoteId") REFERENCES "Deal"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Deal_canonicalQuoteId_idx" ON "Deal"("canonicalQuoteId");
