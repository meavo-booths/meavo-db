-- Factory floor tables (cross-app data review 2026-11, release 1, script 4 of 4):
-- additive, transactional, idempotent DDL only.
-- Apply ONLY after reviewing the target/schema and following RELEASE_POLICY.md.
-- Apply: scripts/apply-sql.sh <staging|production> scripts/add-factory-floor-tables.sql --env-file <file> [--tag vX.Y.Z]
--    or: npx prisma db execute --file scripts/add-factory-floor-tables.sql --schema prisma/schema.prisma
-- Required existing objects: FactoryStation, FactoryElement, FactoryColor, FactoryBoothModel,
-- FactoryProductionBatch, FactoryProductionEvent, FactoryStationElementRequirement.
-- FactoryScrapReportStatus is created here when missing, with the same guarded
-- statement as scripts/add-factory-scrap-approval-settings.sql (the staging branch
-- never received that script; production has the type with the same three values).
--
-- Declares in meavo-db the ten tables and nine columns that the Factory app
-- (pinned to v0.25.0) created at runtime with its ensure*Schema() modules and
-- scripts/sql/*.sql. Every object is written exactly as production had it on
-- 5 November 2026 (information_schema, pg_constraint and pg_indexes read through
-- _shared/tools/prod-read.mjs), including names, defaults, ON UPDATE actions,
-- the UNIQUE constraint of FactoryModelPanelEffort and two indexes Prisma cannot
-- express: FactoryPalletLine_combo_key (expression) and
-- FactoryStationBreak_station_open_key (partial). On production every statement
-- is a no-op; on staging and fresh databases it creates the objects.
-- FactoryProductionEvent.crewWorkerId1/2 stay without a foreign key, as in production.
-- Run twice against an isolated, disposable PostgreSQL DB before environment release.
-- No production application is authorized by this file.
BEGIN;

-- CreateEnum
DO $$ BEGIN
  CREATE TYPE "FactoryPanelOrderSourceKind" AS ENUM ('rp', 'rp_line', 'ip');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "FactoryScrapReportStatus" AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- AlterTable: columns the Factory app added to schema-owned tables.
ALTER TABLE "FactoryStationElementRequirement" ADD COLUMN IF NOT EXISTS "effortUnits" INTEGER;
ALTER TABLE "FactoryProductionBatch" ADD COLUMN IF NOT EXISTS "pauseNote" TEXT;
ALTER TABLE "FactoryProductionEvent"
  ADD COLUMN IF NOT EXISTS "palletId" TEXT,
  ADD COLUMN IF NOT EXISTS "cycleStartedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "cycleSeconds" INTEGER,
  ADD COLUMN IF NOT EXISTS "cycleKind" TEXT,
  ADD COLUMN IF NOT EXISTS "source" TEXT,
  ADD COLUMN IF NOT EXISTS "crewWorkerId1" TEXT,
  ADD COLUMN IF NOT EXISTS "crewWorkerId2" TEXT;

-- CreateTable
CREATE TABLE IF NOT EXISTS "FactoryWorker" (
    "id" TEXT NOT NULL,
    "nameBg" TEXT NOT NULL,
    "pinHash" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryWorker_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryStationAssignment" (
    "id" TEXT NOT NULL,
    "stationId" TEXT NOT NULL,
    "workerId" TEXT NOT NULL,
    "slot" INTEGER NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryStationAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPallet" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "elementId" TEXT,
    "batchId" TEXT,
    "colorId" TEXT,
    "qty" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "location" TEXT NOT NULL DEFAULT 'aksakovo',
    "readyForTransport" BOOLEAN NOT NULL DEFAULT false,
    "readyAt" TIMESTAMP(3),
    "lastUsedAt" TIMESTAMP(3),
    "lastStationId" TEXT,

    CONSTRAINT "FactoryPallet_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPalletLine" (
    "id" TEXT NOT NULL,
    "palletId" TEXT NOT NULL,
    "elementId" TEXT NOT NULL,
    "batchId" TEXT,
    "colorId" TEXT,
    "qty" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryPalletLine_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPalletHold" (
    "id" TEXT NOT NULL,
    "palletId" TEXT NOT NULL,
    "stationId" TEXT NOT NULL,
    "claimedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryPalletHold_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryModelPanelEffort" (
    "id" TEXT NOT NULL,
    "boothModelId" TEXT NOT NULL,
    "elementId" TEXT NOT NULL,
    "effortUnits" INTEGER,

    CONSTRAINT "FactoryModelPanelEffort_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "FactoryModelPanelEffort_boothModelId_elementId_key" UNIQUE ("boothModelId", "elementId")
);

CREATE TABLE IF NOT EXISTS "FactoryStationBreak" (
    "id" TEXT NOT NULL,
    "stationId" TEXT NOT NULL,
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),

    CONSTRAINT "FactoryStationBreak_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPanelOrder" (
    "id" TEXT NOT NULL,
    "sourceKind" "FactoryPanelOrderSourceKind" NOT NULL,
    "sourceId" TEXT NOT NULL,
    "sourceNum" TEXT NOT NULL,
    "stationId" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "scheduleNote" TEXT,
    "qtyRequired" INTEGER NOT NULL DEFAULT 1,
    "qtyGood" INTEGER NOT NULL DEFAULT 0,
    "qtyScrap" INTEGER NOT NULL DEFAULT 0,
    "withdrawnAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryPanelOrder_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPanelOrderEvent" (
    "id" TEXT NOT NULL,
    "panelOrderId" TEXT NOT NULL,
    "stationId" TEXT NOT NULL,
    "qtyGood" INTEGER NOT NULL DEFAULT 0,
    "qtyScrap" INTEGER NOT NULL DEFAULT 0,
    "recordedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "clientEventId" TEXT NOT NULL,
    "scrapNote" TEXT,
    "syncedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryPanelOrderEvent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "FactoryPanelOrderScrapReport" (
    "id" TEXT NOT NULL,
    "panelOrderId" TEXT NOT NULL,
    "panelOrderEventId" TEXT NOT NULL,
    "stationId" TEXT,
    "qty" INTEGER NOT NULL DEFAULT 1,
    "notes" TEXT,
    "status" "FactoryScrapReportStatus" NOT NULL DEFAULT 'pending',
    "resolvedAt" TIMESTAMP(3),
    "resolvedByUserId" TEXT,
    "resolutionNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FactoryPanelOrderScrapReport_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "FactoryWorker_isActive_sortOrder_idx" ON "FactoryWorker"("isActive", "sortOrder");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryStationAssignment_workerId_key" ON "FactoryStationAssignment"("workerId");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryStationAssignment_stationId_slot_key" ON "FactoryStationAssignment"("stationId", "slot");
CREATE INDEX IF NOT EXISTS "FactoryStationAssignment_stationId_idx" ON "FactoryStationAssignment"("stationId");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPallet_code_key" ON "FactoryPallet"("code");
CREATE INDEX IF NOT EXISTS "FactoryPallet_elementId_idx" ON "FactoryPallet"("elementId");
CREATE INDEX IF NOT EXISTS "FactoryPalletLine_palletId_idx" ON "FactoryPalletLine"("palletId");
-- SQL-only: one line per pallet, element, batch and colour, treating null batch/colour as one value.
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPalletLine_combo_key"
  ON "FactoryPalletLine"("palletId", "elementId", COALESCE("batchId", ''::text), COALESCE("colorId", ''::text));
CREATE INDEX IF NOT EXISTS "FactoryPalletHold_palletId_idx" ON "FactoryPalletHold"("palletId");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPalletHold_pallet_station_key" ON "FactoryPalletHold"("palletId", "stationId");
CREATE INDEX IF NOT EXISTS "FactoryStationBreak_stationId_startedAt_idx" ON "FactoryStationBreak"("stationId", "startedAt");
-- SQL-only: at most one open break per station.
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryStationBreak_station_open_key"
  ON "FactoryStationBreak"("stationId") WHERE ("endedAt" IS NULL);
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPanelOrder_sourceKind_sourceId_key" ON "FactoryPanelOrder"("sourceKind", "sourceId");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrder_stationId_sortOrder_idx" ON "FactoryPanelOrder"("stationId", "sortOrder");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrder_withdrawnAt_idx" ON "FactoryPanelOrder"("withdrawnAt");
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPanelOrderEvent_clientEventId_key" ON "FactoryPanelOrderEvent"("clientEventId");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrderEvent_panelOrderId_recordedAt_idx" ON "FactoryPanelOrderEvent"("panelOrderId", "recordedAt" DESC);
CREATE INDEX IF NOT EXISTS "FactoryPanelOrderEvent_stationId_recordedAt_idx" ON "FactoryPanelOrderEvent"("stationId", "recordedAt" DESC);
CREATE UNIQUE INDEX IF NOT EXISTS "FactoryPanelOrderScrapReport_panelOrderEventId_key" ON "FactoryPanelOrderScrapReport"("panelOrderEventId");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrderScrapReport_panelOrderId_status_idx" ON "FactoryPanelOrderScrapReport"("panelOrderId", "status");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrderScrapReport_resolvedAt_createdAt_idx" ON "FactoryPanelOrderScrapReport"("resolvedAt", "createdAt");
CREATE INDEX IF NOT EXISTS "FactoryPanelOrderScrapReport_stationId_idx" ON "FactoryPanelOrderScrapReport"("stationId");
CREATE INDEX IF NOT EXISTS "FactoryProductionEvent_palletId_idx" ON "FactoryProductionEvent"("palletId");
CREATE INDEX IF NOT EXISTS "FactoryProductionEvent_source_recordedAt_idx" ON "FactoryProductionEvent"("source", "recordedAt");
CREATE INDEX IF NOT EXISTS "FactoryProductionEvent_crewWorkerId1_idx" ON "FactoryProductionEvent"("crewWorkerId1");
CREATE INDEX IF NOT EXISTS "FactoryProductionEvent_crewWorkerId2_idx" ON "FactoryProductionEvent"("crewWorkerId2");

-- AddForeignKey (guarded; names and actions as in production).
DO $$
DECLARE fk record;
BEGIN
  FOR fk IN
    SELECT * FROM (VALUES
      ('FactoryStationAssignment', 'FactoryStationAssignment_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryStationAssignment', 'FactoryStationAssignment_workerId_fkey', 'FOREIGN KEY ("workerId") REFERENCES "FactoryWorker"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPallet', 'FactoryPallet_elementId_fkey', 'FOREIGN KEY ("elementId") REFERENCES "FactoryElement"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPallet', 'FactoryPallet_batchId_fkey', 'FOREIGN KEY ("batchId") REFERENCES "FactoryProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPallet', 'FactoryPallet_colorId_fkey', 'FOREIGN KEY ("colorId") REFERENCES "FactoryColor"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPallet', 'FactoryPallet_lastStationId_fkey', 'FOREIGN KEY ("lastStationId") REFERENCES "FactoryStation"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPalletLine', 'FactoryPalletLine_palletId_fkey', 'FOREIGN KEY ("palletId") REFERENCES "FactoryPallet"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPalletLine', 'FactoryPalletLine_elementId_fkey', 'FOREIGN KEY ("elementId") REFERENCES "FactoryElement"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPalletLine', 'FactoryPalletLine_batchId_fkey', 'FOREIGN KEY ("batchId") REFERENCES "FactoryProductionBatch"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPalletLine', 'FactoryPalletLine_colorId_fkey', 'FOREIGN KEY ("colorId") REFERENCES "FactoryColor"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPalletHold', 'FactoryPalletHold_palletId_fkey', 'FOREIGN KEY ("palletId") REFERENCES "FactoryPallet"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPalletHold', 'FactoryPalletHold_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryModelPanelEffort', 'FactoryModelPanelEffort_boothModelId_fkey', 'FOREIGN KEY ("boothModelId") REFERENCES "FactoryBoothModel"("id") ON DELETE CASCADE'),
      ('FactoryModelPanelEffort', 'FactoryModelPanelEffort_elementId_fkey', 'FOREIGN KEY ("elementId") REFERENCES "FactoryElement"("id") ON DELETE CASCADE'),
      ('FactoryStationBreak', 'FactoryStationBreak_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPanelOrder', 'FactoryPanelOrder_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryPanelOrderEvent', 'FactoryPanelOrderEvent_panelOrderId_fkey', 'FOREIGN KEY ("panelOrderId") REFERENCES "FactoryPanelOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPanelOrderEvent', 'FactoryPanelOrderEvent_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE RESTRICT ON UPDATE CASCADE'),
      ('FactoryPanelOrderScrapReport', 'FactoryPanelOrderScrapReport_panelOrderId_fkey', 'FOREIGN KEY ("panelOrderId") REFERENCES "FactoryPanelOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPanelOrderScrapReport', 'FactoryPanelOrderScrapReport_panelOrderEventId_fkey', 'FOREIGN KEY ("panelOrderEventId") REFERENCES "FactoryPanelOrderEvent"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('FactoryPanelOrderScrapReport', 'FactoryPanelOrderScrapReport_stationId_fkey', 'FOREIGN KEY ("stationId") REFERENCES "FactoryStation"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('FactoryProductionEvent', 'FactoryProductionEvent_palletId_fkey', 'FOREIGN KEY ("palletId") REFERENCES "FactoryPallet"("id") ON DELETE SET NULL ON UPDATE CASCADE')
    ) AS t("tbl", "name", "def")
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = fk."name" AND conrelid = format('%I', fk."tbl")::regclass
    ) THEN
      EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I %s', fk."tbl", fk."name", fk."def");
    END IF;
  END LOOP;
END $$;

COMMIT;
