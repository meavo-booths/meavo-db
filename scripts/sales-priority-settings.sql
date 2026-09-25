-- Super Admin-only Sales priority model selection and per-run configuration history.
-- Apply: npx prisma db execute --file scripts/sales-priority-settings.sql --schema prisma/schema.prisma
-- Prerequisite: scripts/sales-daily-priorities.sql has been applied.
-- Additive, transactional and idempotent; no settings or run data are overwritten.
-- Verify the actual isolated non-production target before testing. Production
-- application requires exact SQL/revision approval under RELEASE_POLICY.md.
-- Application rollback must retain this table and historical modelConfig values.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS "SalesPrioritySettings" (
  "id" TEXT NOT NULL DEFAULT 'default',
  "modelProfile" TEXT NOT NULL DEFAULT 'gpt-6-sol',
  "updatedById" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesPrioritySettings_pkey" PRIMARY KEY ("id")
);

-- Prisma cannot express this CHECK. The app creates the row on the first save;
-- absence means the default profile, and no second settings record is permitted.
DO $$ BEGIN
  ALTER TABLE "SalesPrioritySettings"
    ADD CONSTRAINT "SalesPrioritySettings_singleton_check" CHECK ("id" = 'default');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "SalesPriorityRun"
  ADD COLUMN IF NOT EXISTS "modelConfig" JSONB;

-- Legacy runs deliberately remain NULL. Sales interprets their existing model
-- with the legacy low-reasoning profile. New runs capture the full configuration
-- once when initialized; later settings edits affect only subsequently started runs.

COMMIT;
