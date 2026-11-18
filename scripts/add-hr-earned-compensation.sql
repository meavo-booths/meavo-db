-- Apply: scripts/apply-sql.sh staging scripts/add-hr-earned-compensation.sql --env-file <verified-staging-env>
-- Production: approved release tag only. Preserves annual available commission; no historical earnings inferred.
BEGIN;

-- CreateEnum
DO $$ BEGIN
CREATE TYPE "HrEarningKind" AS ENUM ('COMMISSION', 'TEAM_BONUS');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- CreateTable
CREATE TABLE IF NOT EXISTS "HrEarning" (
    "id" TEXT NOT NULL,
    "kind" "HrEarningKind" NOT NULL,
    "employeeId" TEXT,
    "teamId" TEXT,
    "teamName" TEXT NOT NULL DEFAULT '',
    "startMonth" DATE NOT NULL,
    "endMonth" DATE NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "note" TEXT NOT NULL DEFAULT '',
    "requestHash" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "cancelledAt" TIMESTAMP(3),
    "cancelledById" TEXT,
    "cancellationReason" TEXT NOT NULL DEFAULT '',
    "replacesId" TEXT,

    CONSTRAINT "HrEarning_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE IF NOT EXISTS "HrEarningAllocation" (
    "id" TEXT NOT NULL,
    "earningId" TEXT NOT NULL,
    "employeeId" TEXT NOT NULL,
    "month" DATE NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "company" "Company" NOT NULL,

    CONSTRAINT "HrEarningAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "HrEarning_replacesId_key" ON "HrEarning"("replacesId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "HrEarning_employeeId_startMonth_idx" ON "HrEarning"("employeeId", "startMonth");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "HrEarning_teamId_startMonth_idx" ON "HrEarning"("teamId", "startMonth");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "HrEarning_kind_startMonth_idx" ON "HrEarning"("kind", "startMonth");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "HrEarningAllocation_employeeId_month_idx" ON "HrEarningAllocation"("employeeId", "month");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "HrEarningAllocation_month_idx" ON "HrEarningAllocation"("month");

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "HrEarningAllocation_earningId_employeeId_month_key" ON "HrEarningAllocation"("earningId", "employeeId", "month");

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_cancelledById_fkey" FOREIGN KEY ("cancelledById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_replacesId_fkey" FOREIGN KEY ("replacesId") REFERENCES "HrEarning"("id") ON DELETE RESTRICT ON UPDATE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarningAllocation" ADD CONSTRAINT "HrEarningAllocation_earningId_fkey" FOREIGN KEY ("earningId") REFERENCES "HrEarning"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AddForeignKey
DO $$ BEGIN
ALTER TABLE "HrEarningAllocation" ADD CONSTRAINT "HrEarningAllocation_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "Employee"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_amount_check" CHECK ("amount" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_period_check" CHECK (EXTRACT(DAY FROM "startMonth") = 1 AND EXTRACT(DAY FROM "endMonth") = 1 AND "endMonth" >= "startMonth");
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
ALTER TABLE "HrEarning" ADD CONSTRAINT "HrEarning_subject_check" CHECK (("kind" = 'COMMISSION' AND "employeeId" IS NOT NULL) OR ("kind" = 'TEAM_BONUS' AND "employeeId" IS NULL AND "teamId" IS NOT NULL AND "amount" > 0 AND "startMonth" = "endMonth"));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
ALTER TABLE "HrEarningAllocation" ADD CONSTRAINT "HrEarningAllocation_amount_check" CHECK ("amount" >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
ALTER TABLE "HrEarningAllocation" ADD CONSTRAINT "HrEarningAllocation_month_check" CHECK (EXTRACT(DAY FROM "month") = 1);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMIT;
