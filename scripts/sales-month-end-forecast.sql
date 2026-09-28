-- Owner: Sales. Additive, transactional, idempotent; no existing data changed.
-- Apply: npx prisma db execute --file scripts/sales-month-end-forecast.sql --schema prisma/schema.prisma
-- Verify the actual isolated staging target before use. Production application
-- requires approval of this SQL/revision under RELEASE_POLICY.md.
-- Rollback: disable forecast processing / roll back app; retain historical tables.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
CREATE TABLE IF NOT EXISTS "SalesForecastSettings" (
  id TEXT NOT NULL DEFAULT 'default' PRIMARY KEY CHECK (id='default'),
  "modelProfile" TEXT NOT NULL DEFAULT 'gpt-6-sol',
  "processingEnabled" BOOLEAN NOT NULL DEFAULT false,
  "updatedById" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL
);
CREATE TABLE IF NOT EXISTS "SalesForecastRun" (
  id TEXT NOT NULL PRIMARY KEY,
  "runDate" DATE NOT NULL,
  "cutoffAt" TIMESTAMP(3) NOT NULL,
  "capturedAt" TIMESTAMP(3),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','READY','FAILED')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  "leaseToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  model TEXT NOT NULL,
  "modelConfig" JSONB NOT NULL,
  "calculationVersion" TEXT NOT NULL,
  "promptVersion" TEXT NOT NULL,
  inputs JSONB,
  result JSONB,
  briefing JSONB,
  "aiStatus" TEXT NOT NULL DEFAULT 'PENDING' CHECK ("aiStatus" IN ('PENDING','COMPLETE','SKIPPED','FAILED')),
  "aiAttempts" INTEGER NOT NULL DEFAULT 0 CHECK ("aiAttempts" >= 0),
  "inputTokens" INTEGER NOT NULL DEFAULT 0 CHECK ("inputTokens" >= 0),
  "outputTokens" INTEGER NOT NULL DEFAULT 0 CHECK ("outputTokens" >= 0),
  "estimatedUsd" DECIMAL(12,6) NOT NULL DEFAULT 0 CHECK ("estimatedUsd" >= 0),
  "usageIncomplete" BOOLEAN NOT NULL DEFAULT false,
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CHECK (("leaseToken" IS NULL) = ("leaseExpiresAt" IS NULL)),
  CHECK (status <> 'READY' OR (inputs IS NOT NULL AND result IS NOT NULL AND "capturedAt" IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS "SalesForecastRun_runDate_key" ON "SalesForecastRun" ("runDate");
CREATE INDEX IF NOT EXISTS "SalesForecastRun_status_runDate_idx" ON "SalesForecastRun" (status,"runDate");
COMMIT;
