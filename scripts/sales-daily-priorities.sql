-- Sales daily priorities: verified ownership, analysis runs, leased work,
-- point-in-time features, enrichment caches, recommendations, and rep feedback.
-- Apply: npx prisma db execute --file scripts/sales-daily-priorities.sql --schema prisma/schema.prisma
-- Additive and transactional; safe to rerun after a successful application.
-- Verify an isolated non-production target before testing. Production application
-- requires the exact SQL/revision approval described in RELEASE_POLICY.md.
-- Recipient IDs in recommendation/feedback history deliberately have no User
-- foreign key. Follow with sales-admin-priorities.sql for tool roles and names.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS "SalesRepIdentity" (
  "id" TEXT NOT NULL,
  "canonicalName" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "hubspotOwnerId" TEXT,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesRepIdentity_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "SalesPriorityRun" (
  "id" TEXT NOT NULL,
  "runDate" DATE NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "cutoffAt" TIMESTAMP(3) NOT NULL,
  "deadlineAt" TIMESTAMP(3) NOT NULL,
  "model" TEXT NOT NULL,
  "promptVersion" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CONSTRAINT "SalesPriorityRun_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "SalesPriorityWorkItem" (
  "id" TEXT NOT NULL,
  "runId" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "userId" TEXT,
  "familyId" TEXT,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "availableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "leaseToken" TEXT,
  "leaseExpiresAt" TIMESTAMP(3),
  "input" JSONB NOT NULL,
  "result" JSONB,
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  "finishedAt" TIMESTAMP(3),
  CONSTRAINT "SalesPriorityWorkItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "SalesOpportunitySnapshot" (
  "id" TEXT NOT NULL,
  "runId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  "dealId" TEXT NOT NULL,
  "userId" TEXT,
  "capturedAt" TIMESTAMP(3) NOT NULL,
  "data" JSONB NOT NULL,
  CONSTRAINT "SalesOpportunitySnapshot_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "SalesCrmSnapshot" (
  "hubspotDealId" TEXT NOT NULL,
  "payload" JSONB NOT NULL,
  "status" TEXT NOT NULL,
  "fetchedAt" TIMESTAMP(3) NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesCrmSnapshot_pkey" PRIMARY KEY ("hubspotDealId")
);

CREATE TABLE IF NOT EXISTS "SalesCompanyResearch" (
  "domain" TEXT NOT NULL,
  "companyName" TEXT NOT NULL,
  "facts" JSONB NOT NULL,
  "status" TEXT NOT NULL,
  "fetchedAt" TIMESTAMP(3) NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SalesCompanyResearch_pkey" PRIMARY KEY ("domain")
);

CREATE TABLE IF NOT EXISTS "SalesPriorityRecommendation" (
  "id" TEXT NOT NULL,
  "runId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "familyId" TEXT NOT NULL,
  "dealId" TEXT NOT NULL,
  "rank" INTEGER NOT NULL,
  "content" JSONB NOT NULL,
  "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SalesPriorityRecommendation_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "SalesPriorityFeedback" (
  "id" TEXT NOT NULL,
  "recommendationId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SalesPriorityFeedback_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SalesRepIdentity_canonicalName_key"
  ON "SalesRepIdentity"("canonicalName");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesRepIdentity_hubspotOwnerId_key"
  ON "SalesRepIdentity"("hubspotOwnerId");
CREATE INDEX IF NOT EXISTS "SalesRepIdentity_userId_idx"
  ON "SalesRepIdentity"("userId");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesPriorityRun_runDate_key"
  ON "SalesPriorityRun"("runDate");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesPriorityWorkItem_runId_kind_key_key"
  ON "SalesPriorityWorkItem"("runId", "kind", "key");
CREATE INDEX IF NOT EXISTS "SalesPriorityWorkItem_status_availableAt_idx"
  ON "SalesPriorityWorkItem"("status", "availableAt");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesOpportunitySnapshot_runId_familyId_key"
  ON "SalesOpportunitySnapshot"("runId", "familyId");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesPriorityRecommendation_runId_userId_familyId_key"
  ON "SalesPriorityRecommendation"("runId", "userId", "familyId");
CREATE INDEX IF NOT EXISTS "SalesPriorityRecommendation_userId_generatedAt_idx"
  ON "SalesPriorityRecommendation"("userId", "generatedAt");
CREATE UNIQUE INDEX IF NOT EXISTS "SalesPriorityFeedback_recommendationId_userId_kind_key"
  ON "SalesPriorityFeedback"("recommendationId", "userId", "kind");
CREATE INDEX IF NOT EXISTS "SalesPriorityFeedback_userId_idx"
  ON "SalesPriorityFeedback"("userId");

DO $$ BEGIN
  ALTER TABLE "SalesRepIdentity" ADD CONSTRAINT "SalesRepIdentity_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SalesPriorityWorkItem" ADD CONSTRAINT "SalesPriorityWorkItem_runId_fkey"
    FOREIGN KEY ("runId") REFERENCES "SalesPriorityRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SalesOpportunitySnapshot" ADD CONSTRAINT "SalesOpportunitySnapshot_runId_fkey"
    FOREIGN KEY ("runId") REFERENCES "SalesPriorityRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SalesPriorityRecommendation" ADD CONSTRAINT "SalesPriorityRecommendation_runId_fkey"
    FOREIGN KEY ("runId") REFERENCES "SalesPriorityRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "SalesPriorityFeedback" ADD CONSTRAINT "SalesPriorityFeedback_recommendationId_fkey"
    FOREIGN KEY ("recommendationId") REFERENCES "SalesPriorityRecommendation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;
