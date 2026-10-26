-- Idempotent DDL for kiosk problem reports and shared scrap cases.
-- Apply with: prisma db execute --file scripts/add-factory-station-issues.sql
-- Historical FactoryPanelScrapReport rows are closed once, when resolvedAt is added.
-- Safe to run twice: the second run does not close newer open cases.

DO $$ BEGIN
  CREATE TYPE "FactoryScrapProcessStation" AS ENUM (
    'package', 'center', 'edge', 'sand', 'oil', 'glass', 'assembly'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "FactoryScrapReportSource" AS ENUM ('admin', 'kiosk');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "FactoryStationIssueType" AS ENUM ('missing_part', 'wrong_holes', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "FactoryPanelScrapReport" (
  "id" TEXT NOT NULL,
  "batchId" TEXT NOT NULL,
  "boothModelId" TEXT NOT NULL,
  "colorId" TEXT NOT NULL,
  "elementId" TEXT NOT NULL,
  "processStation" "FactoryScrapProcessStation",
  "qty" INTEGER NOT NULL DEFAULT 1,
  "notes" TEXT,
  "protocolNumber" INTEGER,
  "pdfStorageKey" TEXT,
  "recordedByUserId" TEXT,
  "source" "FactoryScrapReportSource" NOT NULL DEFAULT 'admin',
  "stationId" TEXT,
  "productionEventId" TEXT,
  "crewWorkerId1" TEXT,
  "crewWorkerId2" TEXT,
  "resolvedAt" TIMESTAMP(3),
  "resolvedByUserId" TEXT,
  "resolutionNote" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FactoryPanelScrapReport_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPanelScrapPhoto" (
  "id" TEXT NOT NULL,
  "reportId" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "fileName" TEXT,
  "mimeType" TEXT NOT NULL,
  "sizeBytes" INTEGER NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FactoryPanelScrapPhoto_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "protocolNumber" INTEGER;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "pdfStorageKey" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "source" "FactoryScrapReportSource" NOT NULL DEFAULT 'admin';
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "stationId" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "productionEventId" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "crewWorkerId1" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "crewWorkerId2" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "resolvedByUserId" TEXT;
ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN IF NOT EXISTS "resolutionNote" TEXT;

ALTER TABLE "FactoryPanelScrapReport" ALTER COLUMN "recordedByUserId" DROP NOT NULL;
ALTER TABLE "FactoryPanelScrapReport" ALTER COLUMN "processStation" DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'FactoryPanelScrapReport'
      AND column_name = 'resolvedAt'
  ) THEN
    ALTER TABLE "FactoryPanelScrapReport" ADD COLUMN "resolvedAt" TIMESTAMP(3);
    UPDATE "FactoryPanelScrapReport"
      SET "resolvedAt" = "createdAt"
      WHERE "resolvedAt" IS NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPanelScrapReport_protocolNumber_key"
  ON "FactoryPanelScrapReport"("protocolNumber");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPanelScrapReport_productionEventId_key"
  ON "FactoryPanelScrapReport"("productionEventId");
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_batchId_createdAt_idx"
  ON "FactoryPanelScrapReport"("batchId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_recordedByUserId_createdAt_idx"
  ON "FactoryPanelScrapReport"("recordedByUserId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_processStation_idx"
  ON "FactoryPanelScrapReport"("processStation");
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_resolvedAt_createdAt_idx"
  ON "FactoryPanelScrapReport"("resolvedAt", "createdAt");
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapReport_stationId_idx"
  ON "FactoryPanelScrapReport"("stationId");
CREATE INDEX IF NOT EXISTS "FactoryPanelScrapPhoto_reportId_idx"
  ON "FactoryPanelScrapPhoto"("reportId");

DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_batchId_fkey"
    FOREIGN KEY ("batchId") REFERENCES "FactoryProductionBatch"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_boothModelId_fkey"
    FOREIGN KEY ("boothModelId") REFERENCES "FactoryBoothModel"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_colorId_fkey"
    FOREIGN KEY ("colorId") REFERENCES "FactoryColor"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_elementId_fkey"
    FOREIGN KEY ("elementId") REFERENCES "FactoryElement"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_recordedByUserId_fkey"
    FOREIGN KEY ("recordedByUserId") REFERENCES "User"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_stationId_fkey"
    FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_productionEventId_fkey"
    FOREIGN KEY ("productionEventId") REFERENCES "FactoryProductionEvent"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapReport"
    ADD CONSTRAINT "FactoryPanelScrapReport_resolvedByUserId_fkey"
    FOREIGN KEY ("resolvedByUserId") REFERENCES "User"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryPanelScrapPhoto"
    ADD CONSTRAINT "FactoryPanelScrapPhoto_reportId_fkey"
    FOREIGN KEY ("reportId") REFERENCES "FactoryPanelScrapReport"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "FactoryStationIssue" (
  "id" TEXT NOT NULL,
  "clientIssueId" TEXT NOT NULL,
  "stationId" TEXT NOT NULL,
  "deviceId" TEXT,
  "batchId" TEXT,
  "elementId" TEXT,
  "colorId" TEXT,
  "processStep" TEXT,
  "type" "FactoryStationIssueType" NOT NULL,
  "details" TEXT,
  "crewWorkerId1" TEXT,
  "crewWorkerId2" TEXT,
  "reportedAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolvedAt" TIMESTAMP(3),
  "resolvedByUserId" TEXT,
  "resolutionNote" TEXT,
  CONSTRAINT "FactoryStationIssue_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FactoryStationIssue_clientIssueId_key"
  ON "FactoryStationIssue"("clientIssueId");
CREATE INDEX IF NOT EXISTS "FactoryStationIssue_resolvedAt_reportedAt_idx"
  ON "FactoryStationIssue"("resolvedAt", "reportedAt");
CREATE INDEX IF NOT EXISTS "FactoryStationIssue_stationId_idx"
  ON "FactoryStationIssue"("stationId");

DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_stationId_fkey"
    FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_deviceId_fkey"
    FOREIGN KEY ("deviceId") REFERENCES "FactoryDevice"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_batchId_fkey"
    FOREIGN KEY ("batchId") REFERENCES "FactoryProductionBatch"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_elementId_fkey"
    FOREIGN KEY ("elementId") REFERENCES "FactoryElement"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_colorId_fkey"
    FOREIGN KEY ("colorId") REFERENCES "FactoryColor"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE "FactoryStationIssue"
    ADD CONSTRAINT "FactoryStationIssue_resolvedByUserId_fkey"
    FOREIGN KEY ("resolvedByUserId") REFERENCES "User"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
