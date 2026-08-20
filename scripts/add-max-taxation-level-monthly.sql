-- Add FTE extra-tax salary ceiling to CompanyProfile (gateway HR).
-- Apply: npx prisma db execute --file scripts/add-max-taxation-level-monthly.sql --schema prisma/schema.prisma

ALTER TABLE "CompanyProfile"
  ADD COLUMN IF NOT EXISTS "maxTaxationLevelMonthly" DECIMAL(12, 2) NOT NULL DEFAULT 0;
