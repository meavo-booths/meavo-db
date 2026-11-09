-- Discount RRP for the sales app: a third catalog price on Product (Retail deals
-- only) and a flag on QuoteLineItem marking a line discount that was set from it.
-- Additive and idempotent; existing rows get NULL / false.
-- Apply: scripts/apply-sql.sh staging scripts/sales-discount-rrp.sql --env-file <staging env>

BEGIN;

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "discountRrp" DECIMAL(12,2);

ALTER TABLE "QuoteLineItem"
  ADD COLUMN IF NOT EXISTS "discountRrpApplied" BOOLEAN NOT NULL DEFAULT false;

COMMIT;
