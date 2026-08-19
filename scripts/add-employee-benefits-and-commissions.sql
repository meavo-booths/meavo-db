-- Add monthly employee benefits and year-based commissions for gateway HR.
-- Apply: npx prisma db execute --file scripts/add-employee-benefits-and-commissions.sql --schema prisma/schema.prisma

ALTER TABLE "Employee"
  ADD COLUMN IF NOT EXISTS "benefitsMonthly" DECIMAL(12, 2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "EmployeeCommission" (
  "id" TEXT NOT NULL,
  "employeeId" TEXT NOT NULL,
  "year" INTEGER NOT NULL,
  "amount" DECIMAL(12, 2) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "EmployeeCommission_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "EmployeeCommission_employeeId_fkey"
    FOREIGN KEY ("employeeId") REFERENCES "Employee"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "EmployeeCommission_employeeId_year_key"
  ON "EmployeeCommission"("employeeId", "year");

CREATE INDEX IF NOT EXISTS "EmployeeCommission_year_idx"
  ON "EmployeeCommission"("year");
