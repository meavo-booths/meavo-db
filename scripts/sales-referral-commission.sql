-- Referral commission on a sales deal: a fee MEAVO pays a partner (picked from
-- the client directory) on the partner's own invoice. Additive and idempotent;
-- existing deals get no commission (type NULL, amounts 0).
-- Apply: scripts/apply-sql.sh staging scripts/sales-referral-commission.sql --env-file <staging env>

BEGIN;

DO $$ BEGIN
  CREATE TYPE "DealCommissionType" AS ENUM ('PERCENT', 'FIXED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "DealCommissionBasis" AS ENUM ('DEAL_TOTAL', 'BOOTHS_ONLY');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Deal"
  ADD COLUMN IF NOT EXISTS "commissionType" "DealCommissionType",
  ADD COLUMN IF NOT EXISTS "commissionBasis" "DealCommissionBasis" NOT NULL DEFAULT 'DEAL_TOTAL',
  ADD COLUMN IF NOT EXISTS "commissionValue" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "commissionAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "commissionAmountEur" DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "commissionClientId" TEXT,
  ADD COLUMN IF NOT EXISTS "commissionPartnerName" TEXT NOT NULL DEFAULT '';

DO $$ BEGIN
  ALTER TABLE "Deal" ADD CONSTRAINT "Deal_commissionClientId_fkey"
    FOREIGN KEY ("commissionClientId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS "Deal_commissionClientId_idx" ON "Deal"("commissionClientId");

COMMIT;
