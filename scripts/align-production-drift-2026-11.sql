-- Bring a database built from the 0.102.1 schema to the shape production already has
-- (drift map of 6 November 2026, declared in prisma/schema.prisma by 0.103.0):
--   1. DEFAULT CURRENT_TIMESTAMP on 14 updatedAt columns and empty-array defaults on
--      Assembly.issueCategories and Questionnaire.eventTypes;
--   2. the legacy Assembly.issueCategory column;
--   3. Deal.xeroFinalSyncedAt / xeroPaymentSyncedAt as timestamptz, and
--      mrp_one_shot_script.ran_at without an explicit precision;
--   4. the Tasks tables TaskAttachment, TaskIntegration, TaskUserSettings (created by
--      meavo-tasks scripts/add-task-attachments.sql and add-task-user-settings.sql);
--   5. the Zeron material checker's enums and five Zeron* tables (created from its own
--      Prisma schema).
-- Every step checks the catalog first, so on production (and on staging once applied)
-- the script changes nothing. Safe to run repeatedly.

BEGIN;

-- 1. Column defaults, set only where a column has none.
DO $$
DECLARE
  d record;
BEGIN
  FOR d IN
    SELECT * FROM (VALUES
      ('AppAnnouncement', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('AssemblyTeam', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('AssemblyTeamMember', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('LibraryAsset', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('LibraryVideo', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('MrpElectricAssembly', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('MrpMaterialCategory', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('NotificationEventSetting', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('PartnerNotificationPreference', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('SalesPayment', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('SignatureRequest', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('StockPartner', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('UsefulLink', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('UserNotificationPreference', 'updatedAt', 'CURRENT_TIMESTAMP'),
      ('Assembly', 'issueCategories', 'ARRAY[]::TEXT[]'),
      ('Questionnaire', 'eventTypes', 'ARRAY[]::"AssemblyEventType"[]')
    ) AS v(tbl, col, expr)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_attribute a
      WHERE a.attrelid = format('public.%I', d.tbl)::regclass
        AND a.attname = d.col
        AND NOT a.atthasdef
    ) THEN
      EXECUTE format('ALTER TABLE %I ALTER COLUMN %I SET DEFAULT %s', d.tbl, d.col, d.expr);
    END IF;
  END LOOP;
END $$;

-- 2. Legacy single issue category, superseded by issueCategories (Assembly keeps it).
ALTER TABLE "Assembly" ADD COLUMN IF NOT EXISTS "issueCategory" TEXT;

-- 3. Column types. Prisma writes these stamps as UTC, so stored values are read as UTC.
DO $$
DECLARE
  c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['xeroFinalSyncedAt', 'xeroPaymentSyncedAt'] LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_attribute a
      WHERE a.attrelid = 'public."Deal"'::regclass
        AND a.attname = c
        AND a.atttypid = 'timestamp'::regtype
    ) THEN
      EXECUTE format('ALTER TABLE "Deal" ALTER COLUMN %I TYPE TIMESTAMPTZ USING %I AT TIME ZONE ''UTC''', c, c);
    END IF;
  END LOOP;

  -- Same type either way (precision 6 is the default); production has no explicit precision.
  IF EXISTS (
    SELECT 1
    FROM pg_attribute a
    WHERE a.attrelid = to_regclass('public.mrp_one_shot_script')
      AND a.attname = 'ran_at'
      AND a.atttypmod <> -1
  ) THEN
    ALTER TABLE mrp_one_shot_script ALTER COLUMN ran_at TYPE TIMESTAMPTZ;
  END IF;
END $$;

-- 4. Tasks tables.
CREATE TABLE IF NOT EXISTS "TaskAttachment" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "fileName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "byteSize" INTEGER NOT NULL,
  "uploadedById" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskAttachment_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "TaskAttachment_taskId_idx" ON "TaskAttachment"("taskId");

CREATE TABLE IF NOT EXISTS "TaskIntegration" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "accessToken" TEXT,
  "metadata" JSONB NOT NULL DEFAULT '{}',
  "enabled" BOOLEAN NOT NULL DEFAULT true,
  "syncDirection" TEXT NOT NULL DEFAULT 'export',
  "lastSyncAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskIntegration_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "TaskIntegration_userId_idx" ON "TaskIntegration"("userId");
CREATE UNIQUE INDEX IF NOT EXISTS "TaskIntegration_userId_provider_key" ON "TaskIntegration"("userId", "provider");

CREATE TABLE IF NOT EXISTS "TaskUserSettings" (
  "userId" TEXT NOT NULL,
  "slackNotificationsEnabled" BOOLEAN NOT NULL DEFAULT false,
  "slackWebhookUrl" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskUserSettings_pkey" PRIMARY KEY ("userId")
);

-- 5. Zeron material checker enums and tables.
DO $$
BEGIN
  IF to_regtype('public."ZeronImportSourceType"') IS NULL THEN
    CREATE TYPE "ZeronImportSourceType" AS ENUM ('GOOGLE_SHEET_TAB', 'CSV_UPLOAD');
  END IF;
  IF to_regtype('public."ZeronImportStatus"') IS NULL THEN
    CREATE TYPE "ZeronImportStatus" AS ENUM ('PENDING', 'SUCCESS', 'PARTIAL', 'FAILED');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "ZeronSheetState" (
  "id" TEXT NOT NULL DEFAULT 'default',
  "spreadsheetId" TEXT NOT NULL DEFAULT '',
  "lastSyncedAt" TIMESTAMP(3),
  "lastError" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ZeronSheetState_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ZeronImportRun" (
  "id" TEXT NOT NULL,
  "sourceType" "ZeronImportSourceType" NOT NULL,
  "sourceName" TEXT NOT NULL,
  "status" "ZeronImportStatus" NOT NULL DEFAULT 'PENDING',
  "triggeredById" TEXT,
  "rowCount" INTEGER NOT NULL DEFAULT 0,
  "skippedCount" INTEGER NOT NULL DEFAULT 0,
  "errorCount" INTEGER NOT NULL DEFAULT 0,
  "errors" TEXT NOT NULL DEFAULT '[]',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CONSTRAINT "ZeronImportRun_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "ZeronImportRun_createdAt_idx" ON "ZeronImportRun"("createdAt");
CREATE INDEX IF NOT EXISTS "ZeronImportRun_sourceType_idx" ON "ZeronImportRun"("sourceType");

CREATE TABLE IF NOT EXISTS "ZeronImportedTab" (
  "id" TEXT NOT NULL,
  "spreadsheetId" TEXT NOT NULL,
  "tabName" TEXT NOT NULL,
  "contentHash" TEXT NOT NULL,
  "rowCount" INTEGER NOT NULL DEFAULT 0,
  "importedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "importRunId" TEXT,
  CONSTRAINT "ZeronImportedTab_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "ZeronImportedTab_spreadsheetId_idx" ON "ZeronImportedTab"("spreadsheetId");
CREATE UNIQUE INDEX IF NOT EXISTS "ZeronImportedTab_spreadsheetId_tabName_key" ON "ZeronImportedTab"("spreadsheetId", "tabName");

CREATE TABLE IF NOT EXISTS "ZeronDeliveryRow" (
  "id" TEXT NOT NULL,
  "importRunId" TEXT NOT NULL,
  "sourceKey" TEXT NOT NULL,
  "processNumber" TEXT NOT NULL,
  "deliveryDate" TIMESTAMP(3) NOT NULL,
  "itemCode" TEXT NOT NULL,
  "itemName" TEXT NOT NULL DEFAULT '',
  "stockQuantity" TEXT,
  "unit" TEXT,
  "unitCost" TEXT NOT NULL,
  "totalCost" TEXT,
  "warehouse" TEXT,
  "extraCost" TEXT,
  "itemType" TEXT,
  "sourceFileName" TEXT,
  "attachmentPresent" BOOLEAN NOT NULL DEFAULT false,
  "sourceTab" TEXT,
  "sourceType" "ZeronImportSourceType" NOT NULL,
  CONSTRAINT "ZeronDeliveryRow_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "ZeronDeliveryRow_sourceKey_key" ON "ZeronDeliveryRow"("sourceKey");
CREATE INDEX IF NOT EXISTS "ZeronDeliveryRow_itemCode_idx" ON "ZeronDeliveryRow"("itemCode");
CREATE INDEX IF NOT EXISTS "ZeronDeliveryRow_deliveryDate_idx" ON "ZeronDeliveryRow"("deliveryDate");
CREATE INDEX IF NOT EXISTS "ZeronDeliveryRow_processNumber_idx" ON "ZeronDeliveryRow"("processNumber");
CREATE INDEX IF NOT EXISTS "ZeronDeliveryRow_attachmentPresent_idx" ON "ZeronDeliveryRow"("attachmentPresent");
CREATE INDEX IF NOT EXISTS "ZeronDeliveryRow_importRunId_idx" ON "ZeronDeliveryRow"("importRunId");

CREATE TABLE IF NOT EXISTS "ZeronAcceptedUnitCost" (
  "id" TEXT NOT NULL,
  "itemCode" TEXT NOT NULL,
  "itemName" TEXT NOT NULL DEFAULT '',
  "unitCost" TEXT NOT NULL,
  "note" TEXT NOT NULL DEFAULT '',
  "deliveryRowId" TEXT,
  "markedById" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ZeronAcceptedUnitCost_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "ZeronAcceptedUnitCost_itemCode_idx" ON "ZeronAcceptedUnitCost"("itemCode");
CREATE INDEX IF NOT EXISTS "ZeronAcceptedUnitCost_markedById_idx" ON "ZeronAcceptedUnitCost"("markedById");
CREATE UNIQUE INDEX IF NOT EXISTS "ZeronAcceptedUnitCost_itemCode_unitCost_key" ON "ZeronAcceptedUnitCost"("itemCode", "unitCost");

-- Foreign keys, added only where missing (same names and rules as production).
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
      ('TaskAttachment', 'TaskAttachment_taskId_fkey',
       'FOREIGN KEY ("taskId") REFERENCES "Task"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('TaskAttachment', 'TaskAttachment_uploadedById_fkey',
       'FOREIGN KEY ("uploadedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE'),
      ('ZeronImportRun', 'ZeronImportRun_triggeredById_fkey',
       'FOREIGN KEY ("triggeredById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('ZeronImportedTab', 'ZeronImportedTab_importRunId_fkey',
       'FOREIGN KEY ("importRunId") REFERENCES "ZeronImportRun"("id") ON DELETE SET NULL ON UPDATE CASCADE'),
      ('ZeronDeliveryRow', 'ZeronDeliveryRow_importRunId_fkey',
       'FOREIGN KEY ("importRunId") REFERENCES "ZeronImportRun"("id") ON DELETE CASCADE ON UPDATE CASCADE'),
      ('ZeronAcceptedUnitCost', 'ZeronAcceptedUnitCost_markedById_fkey',
       'FOREIGN KEY ("markedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE')
    ) AS v(tbl, name, def)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = format('public.%I', f.tbl)::regclass AND conname = f.name
    ) THEN
      EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I %s', f.tbl, f.name, f.def);
    END IF;
  END LOOP;
END $$;

COMMIT;
