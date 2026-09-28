-- Owner: Sales. Additive and idempotent; keeps all existing forecasts and permissions.
-- Apply on verified staging first. Production SQL requires explicit release approval.
-- Rollback: pause opportunity processing; retain these tables and all history.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
ALTER TABLE "SalesForecastSettings" ADD COLUMN IF NOT EXISTS "opportunityProcessingEnabled" BOOLEAN NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS "SalesOpportunityForecastRun" (
  id TEXT PRIMARY KEY,
  "requestKey" TEXT NOT NULL UNIQUE,
  "runDate" DATE NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('daily','manual')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','READY','PARTIAL','FAILED')),
  "cutoffAt" TIMESTAMP(3) NOT NULL,
  "deadlineAt" TIMESTAMP(3) NOT NULL,
  model TEXT NOT NULL,
  "modelConfig" JSONB NOT NULL,
  "aiAllowed" BOOLEAN NOT NULL,
  version TEXT NOT NULL,
  "promptVersion" TEXT NOT NULL,
  inputs JSONB,
  summary JSONB,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts>=0),
  "leaseToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  "requestedById" TEXT,
  "requestedByName" TEXT,
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CHECK (("leaseToken" IS NULL)=("leaseExpiresAt" IS NULL))
);
CREATE INDEX IF NOT EXISTS "SalesOpportunityForecastRun_date_idx" ON "SalesOpportunityForecastRun" ("runDate" DESC,"createdAt" DESC);
CREATE TABLE IF NOT EXISTS "SalesOpportunityForecastItem" (
  id TEXT PRIMARY KEY,
  "runId" TEXT NOT NULL REFERENCES "SalesOpportunityForecastRun"(id) ON DELETE RESTRICT,
  "familyId" TEXT NOT NULL,
  "dealId" TEXT NOT NULL,
  input JSONB NOT NULL,
  "inputHash" TEXT,
  assessment JSONB,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','COMPLETE','FAILED')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts>=0),
  "leaseToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  "availableAt" TIMESTAMP(3) NOT NULL,
  "inputTokens" INTEGER NOT NULL DEFAULT 0,
  "outputTokens" INTEGER NOT NULL DEFAULT 0,
  "estimatedUsd" DECIMAL(12,6) NOT NULL DEFAULT 0,
  "usageIncomplete" BOOLEAN NOT NULL DEFAULT false,
  "lastError" TEXT,
  "completedAt" TIMESTAMP(3),
  UNIQUE("runId","familyId"),
  CHECK (("leaseToken" IS NULL)=("leaseExpiresAt" IS NULL))
);
CREATE INDEX IF NOT EXISTS "SalesOpportunityForecastItem_claim_idx" ON "SalesOpportunityForecastItem" ("runId",status,"availableAt");
CREATE INDEX IF NOT EXISTS "SalesOpportunityForecastItem_hash_idx" ON "SalesOpportunityForecastItem" ("inputHash","completedAt" DESC);
CREATE INDEX IF NOT EXISTS "SalesOpportunityForecastItem_family_idx" ON "SalesOpportunityForecastItem" ("familyId");
-- Scalar recipient/actor/deal IDs intentionally retain historical identity after deletion.
CREATE TABLE IF NOT EXISTS "SalesOpportunityQualification" (
  "familyId" TEXT PRIMARY KEY,
  data JSONB NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL
);
CREATE TABLE IF NOT EXISTS "SalesOpportunityQualificationEvent" (
  id TEXT PRIMARY KEY,
  "familyId" TEXT NOT NULL,
  data JSONB NOT NULL,
  "actorId" TEXT NOT NULL,
  "actorName" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL
);
CREATE INDEX IF NOT EXISTS "SalesOpportunityQualificationEvent_family_idx" ON "SalesOpportunityQualificationEvent" ("familyId","createdAt");
COMMIT;
