-- Sales: SalesRevenueTarget holds the monthly EUR revenue target per market that the
-- Sales Ops Report (/numbers/ops-report) compares won revenue against. Admins edit it
-- in Sales settings; a missing row means no target for that month and market.
-- Additive, transactional and idempotent; touches no existing data.
-- The month and amount CHECKs are intentional and are not represented in Prisma.
-- Apply: scripts/apply-sql.sh staging scripts/sales-revenue-targets.sql --env-file <staging env>

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS "SalesRevenueTarget" (
  "id"          TEXT NOT NULL,
  "year"        INTEGER NOT NULL,
  "month"       INTEGER NOT NULL,
  "market"      TEXT NOT NULL,
  "amountEur"   DECIMAL(14,2) NOT NULL,
  "updatedById" TEXT,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"   TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesRevenueTarget_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SalesRevenueTarget_year_month_market_key"
  ON "SalesRevenueTarget"("year", "month", "market");

DO $$ BEGIN
  ALTER TABLE "SalesRevenueTarget"
    ADD CONSTRAINT "SalesRevenueTarget_month_check" CHECK ("month" BETWEEN 1 AND 12);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SalesRevenueTarget"
    ADD CONSTRAINT "SalesRevenueTarget_amountEur_check" CHECK ("amountEur" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
