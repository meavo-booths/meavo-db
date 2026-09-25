-- Sales client notes, reusable labels, activity, expenses, and private receipts.
-- Apply: npx prisma db execute --file scripts/client-profile-activity.sql --schema prisma/schema.prisma
-- Apply this script instead of db push: the CHECK constraints are not expressed
-- in Prisma. This is additive and safe to rerun after a successful application.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE "Client" ADD COLUMN IF NOT EXISTS "notes" TEXT NOT NULL DEFAULT '';

DO $$ BEGIN
  CREATE TYPE "ClientEventType" AS ENUM ('DINNER', 'DRINKS', 'MEETING', 'CALL', 'OTHER');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "ClientEventReceiptStatus" AS ENUM ('PENDING', 'READY', 'DELETE_PENDING');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "ClientLabel" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "normalizedName" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ClientLabel_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ClientLabelAssignment" (
  "clientId" TEXT NOT NULL,
  "labelId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ClientLabelAssignment_pkey" PRIMARY KEY ("clientId", "labelId")
);

CREATE TABLE IF NOT EXISTS "ClientEvent" (
  "id" TEXT NOT NULL,
  "clientId" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "eventDate" DATE NOT NULL,
  "type" "ClientEventType" NOT NULL DEFAULT 'OTHER',
  "description" TEXT NOT NULL DEFAULT '',
  "expenseAmount" DECIMAL(12,2),
  "expenseCurrency" TEXT,
  "createdByUserId" TEXT,
  "createdByName" TEXT NOT NULL,
  "updatedByUserId" TEXT,
  "updatedByName" TEXT,
  "editedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  "deletedAt" TIMESTAMP(3),
  CONSTRAINT "ClientEvent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "ClientEventReceipt" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "storageKey" TEXT NOT NULL,
  "fileName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "size" INTEGER NOT NULL,
  "uploadedByUserId" TEXT,
  "uploadExpiresAt" TIMESTAMP(3) NOT NULL,
  "status" "ClientEventReceiptStatus" NOT NULL DEFAULT 'PENDING',
  "cleanupError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ClientEventReceipt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ClientLabel_normalizedName_key"
  ON "ClientLabel"("normalizedName");
CREATE INDEX IF NOT EXISTS "ClientLabelAssignment_labelId_idx"
  ON "ClientLabelAssignment"("labelId");
CREATE INDEX IF NOT EXISTS "ClientEvent_clientId_deletedAt_eventDate_id_idx"
  ON "ClientEvent"("clientId", "deletedAt", "eventDate", "id");
CREATE UNIQUE INDEX IF NOT EXISTS "ClientEventReceipt_storageKey_key"
  ON "ClientEventReceipt"("storageKey");
CREATE INDEX IF NOT EXISTS "ClientEventReceipt_eventId_status_idx"
  ON "ClientEventReceipt"("eventId", "status");
CREATE INDEX IF NOT EXISTS "ClientEventReceipt_status_createdAt_idx"
  ON "ClientEventReceipt"("status", "createdAt");

DO $$ BEGIN
  ALTER TABLE "ClientLabelAssignment" ADD CONSTRAINT "ClientLabelAssignment_clientId_fkey"
    FOREIGN KEY ("clientId") REFERENCES "Client"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientLabelAssignment" ADD CONSTRAINT "ClientLabelAssignment_labelId_fkey"
    FOREIGN KEY ("labelId") REFERENCES "ClientLabel"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEvent" ADD CONSTRAINT "ClientEvent_clientId_fkey"
    FOREIGN KEY ("clientId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEvent" ADD CONSTRAINT "ClientEvent_createdByUserId_fkey"
    FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEvent" ADD CONSTRAINT "ClientEvent_updatedByUserId_fkey"
    FOREIGN KEY ("updatedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEventReceipt" ADD CONSTRAINT "ClientEventReceipt_eventId_fkey"
    FOREIGN KEY ("eventId") REFERENCES "ClientEvent"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEventReceipt" ADD CONSTRAINT "ClientEventReceipt_uploadedByUserId_fkey"
    FOREIGN KEY ("uploadedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientLabel" ADD CONSTRAINT "ClientLabel_normalizedName_check"
    CHECK ("normalizedName" <> '' AND "normalizedName" = lower(btrim("name")));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "ClientEvent" ADD CONSTRAINT "ClientEvent_expense_check"
    CHECK (
      ("expenseAmount" IS NULL AND "expenseCurrency" IS NULL)
      OR (
        "expenseAmount" IS NOT NULL AND "expenseAmount" >= 0
        AND "expenseCurrency" IS NOT NULL
        AND "expenseCurrency" IN ('EUR', 'GBP', 'USD', 'CZK')
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
