-- Idempotent DDL for supervisor scrap approval and Factory settings.
-- Apply with: prisma db execute --file scripts/add-factory-scrap-approval-settings.sql
-- When status is first added, open kiosk cases become pending; everything else is approved.

DO $$ BEGIN
  CREATE TYPE "FactoryScrapReportStatus" AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'FactoryPanelScrapReport'
      AND column_name = 'status'
  ) THEN
    ALTER TABLE "FactoryPanelScrapReport"
      ADD COLUMN "status" "FactoryScrapReportStatus" NOT NULL DEFAULT 'approved';
    UPDATE "FactoryPanelScrapReport"
      SET "status" = 'pending'
      WHERE "source" = 'kiosk' AND "resolvedAt" IS NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_batchId_status_idx"
  ON "FactoryPanelScrapReport"("batchId", "status");

CREATE TABLE IF NOT EXISTS "FactorySetting" (
  "key" TEXT NOT NULL,
  "value" JSONB NOT NULL,
  "updatedByUserId" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FactorySetting_pkey" PRIMARY KEY ("key")
);
