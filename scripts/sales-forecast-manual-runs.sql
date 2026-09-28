-- Owner: Sales. Additive manual historical forecasts; existing daily runs untouched.
-- Apply: npx prisma db execute --file scripts/sales-forecast-manual-runs.sql --schema prisma/schema.prisma
-- Verify isolated staging before applying. Production requires specific approval.
-- Rollback: roll back app code; retain manual runs and cost history.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
CREATE TABLE IF NOT EXISTS "SalesForecastManualRun" (
  id TEXT NOT NULL PRIMARY KEY,
  "runDate" DATE NOT NULL,
  "deadlineAt" TIMESTAMP(3) NOT NULL,
  "requestedById" TEXT,
  "requestedByName" TEXT,
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
CREATE INDEX IF NOT EXISTS "SalesForecastManualRun_runDate_createdAt_idx" ON "SalesForecastManualRun" ("runDate","createdAt");
CREATE INDEX IF NOT EXISTS "SalesForecastManualRun_status_deadlineAt_idx" ON "SalesForecastManualRun" (status,"deadlineAt");
COMMIT;
