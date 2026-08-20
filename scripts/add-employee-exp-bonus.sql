-- Add experience bonus initial percent on Employee for gateway HR.
-- The effective percent grows 0.6pp every 12 months of tenure (computed in app code).
-- Apply: npx prisma db execute --file scripts/add-employee-exp-bonus.sql --schema prisma/schema.prisma

ALTER TABLE "Employee"
  ADD COLUMN IF NOT EXISTS "expBonusInitialPercent" DECIMAL(5, 2) NOT NULL DEFAULT 0;
